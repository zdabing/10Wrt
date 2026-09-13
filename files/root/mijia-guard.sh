#!/bin/sh
# mijia-guard - 小米CDN节点池体检与自动规避
# 背景: 小米CDN池中混有"80端口静默丢弃SYN"的节点, 米家App拿到这种IP会卡设备页。
# 本脚本每15分钟:
#   1) 通过外部DNS动态发现池子IP(附加已知种子IP)
#   2) 逐个体检: 80通=good / 80不通443通=bad80 / 全不通=dead
#   3) /etc/hosts 把 api.io.mi.com / ot.io.mi.com 钉定到健康IP(带标记, 自愈更新)
#   4) nft DNAT 兜底: LAN发往坏节点80端口的连接改道到健康节点(覆盖App内置HTTPDNS绕过路由器DNS的情况)

LOG=/root/mijia-guard.log
NFT_FILE=/etc/mijia-fix.nft
STATE_PINS=/tmp/mijia-guard.pins
STATE_NFT=/tmp/mijia-guard.nft.md5
RESOLVER=223.5.5.5
DOMAINS="api.io.mi.com ot.io.mi.com userio.io.mi.com io.mi.com api.home.mi.com"
PIN_DOMAINS="api.io.mi.com ot.io.mi.com"
SEEDS="111.206.191.135 111.206.191.142 111.206.191.146 111.206.174.193 111.206.174.204 120.52.181.49 120.52.181.52 123.125.102.215"
MARKER="# mijia-guard"

log(){ echo "$(date '+%F %T') $*" >> "$LOG"; }

wait_wan(){
	n=0
	while [ $n -lt 20 ]; do
		ping -c1 -W2 "$RESOLVER" >/dev/null 2>&1 && return 0
		n=$((n+1)); sleep 3
	done
	return 1
}

in_list(){ case " $1 " in *" $2 "*) return 0;; *) return 1;; esac; }

wait_wan || { log "WARN wan not ready, skip"; exit 1; }

# ---- 1. 收集候选IP: 种子 + 外部DNS解析
CAND=""
for ip in $SEEDS; do in_list "$CAND" "$ip" || CAND="$CAND $ip"; done
for d in $DOMAINS; do
	for ip in $(nslookup "$d" "$RESOLVER" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -vE '^(127\.|10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|223\.5\.5\.5$)' | sort -u); do
		in_list "$CAND" "$ip" || CAND="$CAND $ip"
	done
done

# ---- 2. 体检
GOOD=""; BAD80=""; DEAD=""
for ip in $CAND; do
	if curl -m 2 -s -o /dev/null "http://$ip/"; then
		GOOD="$GOOD $ip"
	elif curl -m 2 -sk -o /dev/null "https://$ip/"; then
		BAD80="$BAD80 $ip"
	else
		DEAD="$DEAD $ip"
	fi
done

TGT=$(echo $GOOD | awk '{print $1}')
log "pool=$(echo $CAND | wc -w) good=$(echo $GOOD | wc -w) bad80=$(echo $BAD80 | wc -w) dead=$(echo $DEAD | wc -w) good=[$(echo $GOOD)] tgt=$TGT"

# ---- 3. /etc/hosts 钉定到健康IP
PIN_BLOCK=""
if [ -n "$TGT" ]; then
	for d in $PIN_DOMAINS; do
		for ip in $(echo $GOOD | awk '{print $1" "$2}'); do
			PIN_BLOCK="${PIN_BLOCK}${ip} ${d} ${MARKER}
"
		done
	done
fi
if [ -n "$PIN_BLOCK" ]; then
	if [ "$(cat $STATE_PINS 2>/dev/null)" != "$PIN_BLOCK" ]; then
		sed -i "\@$MARKER@d" /etc/hosts
		printf '%s\n' "$PIN_BLOCK" >> /etc/hosts
		printf '%s' "$PIN_BLOCK" > $STATE_PINS
		/etc/init.d/dnsmasq restart >/dev/null 2>&1
		log "hosts pinned: $TGT $(echo $GOOD | awk '{print $2}') -> $PIN_DOMAINS"
	fi
else
	if [ -s $STATE_PINS ]; then
		sed -i "\@$MARKER@d" /etc/hosts
		rm -f $STATE_PINS
		/etc/init.d/dnsmasq restart >/dev/null 2>&1
		log "WARN no healthy node, pins removed"
	fi
fi

# ---- 4. nft DNAT 兜底
if [ -n "$TGT" ]; then
	BADALL=$(echo $BAD80 $DEAD | tr ' ' '\n' | sort -u | tr '\n' ' ')
	{
		echo "table inet mijia_fix {"
		echo "	set mi_bad80 {"
		echo "		type ipv4_addr"
		[ -n "$BADALL" ] && echo "		elements = { $(echo $BADALL | sed 's/ *$//; s/ /, /g') }"
		echo "	}"
		if [ -n "$DEAD" ]; then
			echo "	set mi_dead {"
			echo "		type ipv4_addr"
			echo "		elements = { $(echo $DEAD | sed 's/ *$//; s/ /, /g') }"
			echo "	}"
		fi
		echo "	chain pre {"
		echo "		type nat hook prerouting priority -110; policy accept;"
		echo '		iifname "br-lan" tcp dport 80 ip daddr @mi_bad80 counter dnat ip to '"$TGT:80"
		[ -n "$DEAD" ] && echo '		iifname "br-lan" ip daddr @mi_dead counter dnat ip to '"$TGT"
		echo "	}"
		echo "}"
	} > $NFT_FILE

	MD5=$(md5sum $NFT_FILE | awk '{print $1}')
	if [ "$MD5" != "$(cat $STATE_NFT 2>/dev/null)" ]; then
		nft list table inet mijia_fix >/dev/null 2>&1 && nft delete table inet mijia_fix
		if nft -f $NFT_FILE 2>> $LOG; then
			echo "$MD5" > $STATE_NFT
			log "nft updated: bad80=[$(echo $BADALL)] dead=[$(echo $DEAD)] tgt=$TGT"
		else
			log "ERROR nft apply failed, see above"
		fi
	fi
else
	log "ERROR no healthy CDN node, nft unchanged"
fi

# ---- 5. 日志瘦身
if [ -f $LOG ] && [ "$(wc -l < $LOG)" -gt 500 ]; then
	tail -n 200 $LOG > $LOG.tmp && mv $LOG.tmp $LOG
fi
exit 0
