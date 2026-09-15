#!/bin/sh
# mijia-bypass-test - 验证 mijia-guard 的 "LAN 入口旁路" 是否真的命中
#
# 为什么不能在本机 curl 了事:
#   兜底规则是 nft prerouting 上的 iifname "br-lan" DNAT, 只有 "从 LAN 口进来" 的包才命中。
#   路由器本机发出的包走 OUTPUT/local 路径, 输入接口根本不是 br-lan, 永远命不中这条规则,
#   所以本机 curl 坏节点拿到成功也证明不了旁路生效 —— 那是假阳性, 本脚本不做这种兜底。
#
# 本脚本的做法: 用 veth 对 + network namespace 造一台假 LAN 客户端,
#   veth 主机端挂进 br-lan, 客户端在 netns 里发请求, 包就是实打实从 LAN 入口进来的。
#
# 三重取证:
#   1) 对照组: 客户端直连健康节点 (不该命中 bad80 规则) —— 先证明"测试客户端这条路是通的",
#      否则主探针计数不增长就分不清是规则没命中还是客户端本身不通
#   2) 主探针: 客户端访问坏节点 80, 读该规则的 counter 增量 —— 计数增长=旁路命中
#   3) conntrack: 确认这条连接被 DNAT 到了健康节点
#
# 用法: mijia-bypass-test.sh [-t 超时秒] [-v] [-m]
#   -t 单次请求超时(默认 5 秒)  -v 打印原始证据  -m 只打印手工验证步骤后退出
#   退出码: 0=旁路命中  1=旁路未命中  2=环境不具备(未测, 不能当通过)  3=当前没有可测的坏节点

set -u

TIMEOUT=5
VERBOSE=0
NS=mibypass
VH=mibypass0
VN=mibypass1
CLIENT=""
NS_CREATED=0

log(){ echo "$*"; }
vlog(){ [ "$VERBOSE" = 1 ] && echo "  [证据] $*"; return 0; }

manual(){
	cat <<'EOF'
手工验证(不需要任何内核模块, 结果同样有效):
  1) 找一台真正接在 LAN 口的机器(PC/手机/另一台路由器), 在它上面执行:
       curl -m 5 -v http://<坏节点IP>/
     注意是 <坏节点IP>, 不是健康节点 —— 坏节点 80 端口是静默丢弃 SYN 的,
     正常情况必然超时, 只有旁路生效才会立刻拿到响应。
  2) 回到路由器上, 看规则计数是否增长:
       nft list chain inet mijia_fix pre
     找到 ip daddr @mi_bad80 那条, 它的 counter packets 应该比测试前大。
  3) 再看连接是否被改道:
       grep 'src=<客户端IP> ' /proc/net/nf_conntrack
     回程元组里应该出现健康节点地址(DNAT 后的目标), 而不是坏节点。
  三样都对上, 才算旁路生效。
EOF
}

while getopts "t:vm" opt; do
	case "$opt" in
		t) TIMEOUT="$OPTARG" ;;
		v) VERBOSE=1 ;;
		m) manual; exit 0 ;;
		*) echo "用法: $0 [-t 超时秒] [-v] [-m]"; exit 2 ;;
	esac
done

[ "$(id -u)" = 0 ] || { log "需要 root 运行"; exit 2; }

for cmd in nft ip curl; do
	command -v "$cmd" >/dev/null 2>&1 || { log "缺少命令: $cmd"; exit 2; }
done

cleanup(){
	# 先删 namespace(连它的 veth 端一起消失), 再兜底删主机端; 失败也无所谓
	[ "$NS_CREATED" = 1 ] && ip netns del "$NS" >/dev/null 2>&1
	ip link del "$VH" >/dev/null 2>&1
	return 0
}
trap cleanup EXIT INT TERM

# ---- 0. 前置检查: 规则表 / LAN 桥是否存在
nft list table inet mijia_fix >/dev/null 2>&1 || {
	log "未找到 nft 表 inet mijia_fix —— 先跑一次 /root/mijia-guard.sh"
	exit 3
}
ip link show br-lan >/dev/null 2>&1 || { log "找不到 br-lan, 本脚本按 br-lan 入口设计"; exit 2; }

# ---- 1. 从当前规则里取出坏节点和改道目标
BAD=$(nft list set inet mijia_fix mi_bad80 2>/dev/null | tr -d '\n' \
	| sed -n 's/.*elements = {[[:space:]]*\([0-9][0-9.]*\).*/\1/p')
TGT=$(nft list chain inet mijia_fix pre 2>/dev/null \
	| sed -n 's/.*dnat ip to \([0-9][0-9.]*\):80.*/\1/p' | head -1)

if [ -z "$BAD" ] || [ -z "$TGT" ]; then
	log "当前没有可测目标: bad80 集合为空或取不到改道目标"
	log "  (说明这一轮体检没发现'80 不通'的坏节点, 旁路规则没生成, 不是规则有问题)"
	[ -n "$TGT" ] && log "  改道目标 TGT=$TGT"
	exit 3
fi
log "坏节点 BAD=$BAD   改道目标 TGT=$TGT"

# ---- 2. 计数基线
rule_pkts(){
	nft list chain inet mijia_fix pre 2>/dev/null | grep '@mi_bad80' \
		| sed -n 's/.*packets \([0-9][0-9]*\).*/\1/p' | head -1
}
CNT0=$(rule_pkts)
case "$CNT0" in ''|*[!0-9]*) CNT0=0 ;; esac
vlog "bad80 规则当前计数: $CNT0"

# ---- 3. 腾一个测试客户端地址(取 LAN 段 .250-.254, 避开默认 DHCP 池 .100-.249)
BLADDR=$(ip -4 -o addr show dev br-lan | awk '{print $4}' | head -1)
[ -n "$BLADDR" ] || { log "br-lan 没有 IPv4 地址"; exit 2; }
GW=${BLADDR%%/*}
PREFIX=${BLADDR##*/}
case "$PREFIX" in ''|*[!0-9]*) PREFIX=24 ;; esac
if [ "$PREFIX" -gt 24 ]; then
	log "br-lan 掩码是 /$PREFIX, 腾不出测试地址(需要 /24 或更宽) —— 未测"
	exit 2
fi
BASE=${GW%.*}
i=250
while [ "$i" -le 254 ]; do
	ping -c1 -W1 "$BASE.$i" >/dev/null 2>&1 || { CLIENT="$BASE.$i"; break; }
	i=$((i + 1))
done
[ -n "$CLIENT" ] || { log "LAN 里 $BASE.250-254 都被占用, 腾不出测试地址 —— 未测"; exit 2; }
log "测试客户端地址: $CLIENT/$PREFIX  网关: $GW"

# ---- 4. 造 veth 对: 主机端进 br-lan, 对端丢进 netns 当假客户端
ip netns del "$NS" >/dev/null 2>&1
ip link del "$VH" >/dev/null 2>&1

if ! ip link add "$VH" type veth peer name "$VN" 2>/tmp/mibypass.err; then
	log "环境不具备: 内核里没有 veth 虚拟网卡模块"
	vlog "$(cat /tmp/mibypass.err 2>/dev/null)"
	cat <<'EOF'
  编译期修: configs/*.seed 里的 CONFIG_PACKAGE_kmod-veth=y (已加), 重新编译刷机后自带
  运行期试: 本固件是 apk 构建, 没有 opkg, 命令是 "apk add kmod-veth";
            但自建内核的模块校验码通常和官方源对不上, 装不上是常态, 别指望它
  不退回回环测试: 本机 curl 坏节点走 OUTPUT, 不经过 br-lan 入口, 命不中旁路规则,
                拿到"成功"是假阳性, 所以这里只能报"未测"
EOF
	manual
	exit 2
fi
[ -s /tmp/mibypass.err ] && vlog "$(cat /tmp/mibypass.err)"

if ! ip netns add "$NS" 2>/tmp/mibypass.err; then
	log "环境不具备: 创建 network namespace 失败(内核缺 CONFIG_NET_NS 或 ip-full 不支持)"
	vlog "$(cat /tmp/mibypass.err 2>/dev/null)"
	rm -f /tmp/mibypass.err
	manual
	exit 2
fi
NS_CREATED=1

ip link set "$VN" netns "$NS" 2>/tmp/mibypass.err || { log "把 veth 对端移入 netns 失败"; exit 2; }
ip link set "$VH" master br-lan up 2>/tmp/mibypass.err || {
	log "把 veth 主机端挂到 br-lan 失败"; vlog "$(cat /tmp/mibypass.err 2>/dev/null)"; exit 2; }
ip -n "$NS" addr add "$CLIENT/$PREFIX" dev "$VN" || exit 2
ip -n "$NS" link set "$VN" up || exit 2
ip -n "$NS" link set lo up || exit 2
ip -n "$NS" route add default via "$GW" || exit 2
rm -f /tmp/mibypass.err

probe(){ # $1=目标IP  $2=超时, 输出 http_code(失败时是 000 或空)
	ip netns exec "$NS" curl -m "$2" -s -o /dev/null -w '%{http_code}' "http://$1/" 2>/dev/null
}

# ---- 5. 对照组: 客户端直连健康节点, 这条路必须通, 且不该命中 bad80 规则
sleep 1
CTRL_CODE=$(probe "$TGT" "$TIMEOUT")
CNT_CTRL=$(rule_pkts)
case "$CNT_CTRL" in ''|*[!0-9]*) CNT_CTRL=0 ;; esac

case "$CTRL_CODE" in
	''|000)
		log "对照组失败: 假客户端连健康节点 $TGT:80 都拿不到响应 —— 测试环境本身不通, 未测"
		log "  (常见原因: LAN 出口防火墙、客户端地址冲突、桥接没生效)"
		manual
		exit 2
		;;
esac
if [ "$CNT_CTRL" != "$CNT0" ]; then
	log "对照组异常: 访问健康节点竟然命中了 bad80 规则计数($CNT0 -> $CNT_CTRL), 规则集合可能重叠"
	exit 1
fi
log "对照组通过: 客户端 -> $TGT 返回 $CTRL_CODE, bad80 计数未变($CNT0)"

# ---- 6. 主探针: 客户端访问坏节点 80, 看旁路有没有把它接走
CODE=$(probe "$BAD" "$TIMEOUT")
RC=$?
CNT1=$(rule_pkts)
case "$CNT1" in ''|*[!0-9]*) CNT1=0 ;; esac
DELTA=$((CNT1 - CNT0))
[ "$DELTA" -lt 0 ] && DELTA=0

CT=""
[ -r /proc/net/nf_conntrack ] && CT=$(grep "src=$CLIENT " /proc/net/nf_conntrack 2>/dev/null | head -1)

vlog "curl 退出码=$RC  http_code=$CODE"
vlog "bad80 规则计数: $CNT0 -> $CNT1 (增量 $DELTA)"
vlog "conntrack: ${CT:-不可用}"

if [ "$DELTA" -lt 1 ]; then
	log "结论: 旁路未命中 —— 包没有从 br-lan 入口进入 prerouting"
	log "  (对照组已证明客户端通路正常, 所以问题在规则侧: 规则被删/表被重载/iifname 不匹配)"
	exit 1
fi

case "$CODE" in
	''|000)
		log "结论: 规则命中了(计数 +$DELTA), 但改道后拿不到响应 —— 旁路没把连接真正接走"
		log "  查 $TGT:80 是否可达, 以及 WAN 侧回程/防火墙"
		exit 1
		;;
esac

case "$CT" in
	*"src=$TGT "*) log "conntrack 确认: 连接已被 DNAT 到 $TGT" ;;
	"") log "conntrack 不可读(/proc/net/nf_conntrack 缺失), 跳过该项取证" ;;
	*) log "注意: conntrack 里没有看到指向 $TGT 的回程元组, 请人工复核上面这行" ;;
esac

log "结论: 旁路生效 —— LAN 入口($CLIENT)访问坏节点 $BAD 命中规则(+$DELTA), 响应 $CODE"
exit 0
