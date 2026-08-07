# 升级后网络故障排查指南

## 场景一：不保留配置升级

**现象：** 点击升级（不保留配置）→ PPPoE 拨号成功有 IP → 但上不了网 → 重启一次后正常。

### 原因

首次启动时 `wan_6`（IPv6）的 Router Solicitation 请求失败，触发了 PPPoE 链路断开重拨。重拨过程中有脚本报错，导致 nftables 防火墙转发规则加载不完整，LAN 设备无法上网。

### 已实施的修复

`files/etc/hotplug.d/iface/99-wan-fix` 会在 WAN 拨号稳定后：
1. 延时 5 秒等待接口就绪
2. 重启防火墙，确保转发规则、flow offload、MSS 钳制全部生效
3. 清理失效的 conntrack 条目

如果升级后仍有此问题，请运行以下命令收集信息：

```bash
# 1. 检查防火墙是否正常加载
logread | grep -i "firewall\|nftables" | tail -20

# 2. 检查 nftables 规则集
nft list ruleset | head -50

# 3. 测试路由器本身能否上网
ping -c 2 223.5.5.5

# 4. 查看 hotplug 脚本是否执行
logread | grep "wan-fix"
```

---

## 场景二：保留配置升级

**现象：** 勾选"保留配置"升级 → PPPoE 拨号成功有 IP → 上不了网 → 重启后正常。

### 可能原因（按可能性排序）

| 优先级 | 可能原因 | 说明 |
|--------|---------|------|
| 🔴高 | nftables 规则集不兼容 | 新版防火墙（fw4/nftables）规则语法变化，老配置生成的规则加载失败，重启后完整 restart 才正常 |
| 🟠中 | pppd 版本变更 | 新 pppd 与旧状态文件冲突，导致转发异常 |
| 🟠中 | 内核模块接口变化 | 新内核中 nft/flow offload 等模块接口变化，旧配置加载异常 |
| 🟡低 | 进程残留 | 升级后旧进程（dnsmasq/netifd）未完全重启 |

### 排查步骤

下次升级后**不要重启**，SSH 进路由器依次执行：

#### 第 1 步：确认基础连通性
```bash
# 测试路由器本身能否上网
ping -c 2 223.5.5.5
# 如果能通，说明问题在转发或 LAN 侧
# 如果不能通，问题在路由器自身
```

#### 第 2 步：检查防火墙加载状态
```bash
# 查看防火墙启动日志
logread | grep -i "firewall\|nftables" | tail -30
# 正常应看到 "Reloading firewall due to ifup of wan" 无报错
```

#### 第 3 步：检查 nftables 规则完整性
```bash
# 查看规则集
nft list ruleset | head -80
# 重点关注 forward 链是否有 forward_lan 和 forward_wan
# 以及 forward_lan 链中是否有 accept 规则
```

#### 第 4 步：检查路由表
```bash
ip route show
# 应该看到 default via x.x.x.x dev pppoe-wan
ip rule show
# 应该只有 3 条标准规则
```

#### 第 5 步：检查 pppd 进程
```bash
ps w | grep pppd | grep -v grep
# 应该看到 pppd 正在运行
```

#### 第 6 步：查看关键错误
```bash
logread | grep -E "pppd|pppoe|out of range|Entry not found" | tail -20
```

### 收集完整诊断信息

将以下命令的输出全部保存并贴给开发者：

```bash
{
echo "=== 接口状态 ==="
ifstatus wan
echo "=== 路由表 ==="
ip route show
echo "=== 防火墙日志 ==="
logread | grep -i "firewall\|nftables" | tail -30
echo "=== nftables 规则集 ==="
nft list ruleset 2>/dev/null | head -80
echo "=== pppd 进程 ==="
ps w | grep pppd | grep -v grep
echo "=== 错误日志 ==="
logread | grep -E "out of range|Entry not found|pppd|pppoe" | tail -20
}
```

---

## 场景三：升级后完全无法拨号

**现象：** 升级后 WAN 口无法获取 IP。

### 排查

```bash
# 检查物理连接
swconfig dev switch0 show 2>/dev/null
# 检查网卡是否识别
ip link show eth1
# 查看 pppoe 相关日志
logread | grep -i "pppoe\|pppd" | tail -30
```

---

## 场景四：外网访问 NAS 仍被限速（nf_deaf 不生效）

**背景：** 固件已内置 nf_deaf（绕过运营商 DPI 限速）。若外网访问 NAS 上行仍只有 5M 左右，按以下顺序排查。

**⚠️ 前置一步：优先试 IPv6 直连**

江苏联通等联通系宽带（V2EX [t/1210042](https://www.v2ex.com/t/1210042) 实测）：**WAN 口 IPv6 地址不受上行限速**，走 IPv6 直连是最可靠的绕过方案，且无需任何伪装模块。

```bash
# 1. 确认有公网 IPv6 地址
ip -6 addr show br-lan | grep 'scope global'

# 2. 用 IPv6 访问外部 NAS（假设其有 IPv6）
ssh -6 user@<NAS-IPv6>
# 或下载测速：curl -6 -o /dev/null <NAS-IPv6 下载链接>

# 3. 外网访问家里 NAS：给 DDNS 配 AAAA 记录，或用 Tailscale 走 IPv6 组网
#    实测 IPv6 能跑满上行，IPv4 仍是 5M
```

如果 NAS 只有 IPv4、必须走 IPv4，再继续下方步骤。

#### 第 1 步：模块是否加载

```bash
lsmod | grep nf_deaf
# 无输出 = 模块未加载，执行：modprobe nf_deaf
```

#### 第 2 步：打标规则是否生效

```bash
nft list chain inet fw4 nf_deaf_postrouting
# 应看到：跳过私有地址 → 公网 IPv4 TCP 大包打 0xDEA10103（无 ct mark 去重）
# 规则缺失 = /etc/nftables.d/10-nf-deaf.nft 未被 include，重启防火墙或检查文件
# ⚠️ 不要改回带 ct mark set 的写法：实测 ct mark set + meta mark set 同规则会导致
#    packet mark 失效、注入不触发（见 README「已知问题」，v29 起已移除）
```

#### 第 3 步：确认注入包真的发出

```bash
# 在访问 NAS 的同时抓 WAN 口发包，应看到 TTL=3 的 http 包（Host: www.speedtest.cn）
tcpdump -i wan -nn 'tcp port 80 and ip[8] == 3' -c 20
# 无注入包：确认规则用 meta length gt 120（大包才触发）、连接未被排除
```

#### 第 4 步：切换注入特征（联通系 DPI 关键）

上海联通实测：DPI 按 **HTTPS SNI** 匹配白名单（443/8080 + SNI 含 `speedtest` 解除限速），明文 HTTP `Host` 特征可能不被识别。切换为 TLS SNI 特征（SNI=`speedtest.cn`）：

```bash
echo -n '1603010044010000400303000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f00000413011302010000130000000f00000c7370656564746573742e636e' | xxd -r -p > /sys/kernel/debug/nf_deaf/buf
```

切换后重跑第 3 步抓包：注入包应变为 TTL=3 的 TLS ClientHello（`tcpdump -i wan -nn 'tcp[12:4] & 0x0fff == 0x1603'`）。若访问 NAS 本身是 HTTPS（带 SNI），也可直接给 NAS 的 TLS 证书配 `speedtest.cn` 备用 SAN，让真实流量自带白名单 SNI（对应 t/1210042 的 SNI 白名单机制）。

#### 第 5 步：运营商策略不支持

V2EX 社区反馈该方案在部分运营商/地区无效（DPI 策略不同）。确认无效可整体关闭：

```bash
rmmod nf_deaf
```

常见误判：外网访问走的是 **IPv6**（本固件 nf_deaf 默认只处理 IPv4），或流量被代理工具接管走了代理链路（排除代理节点 IP 后直连测试）。

---

## 场景五：nf_deaf 注入正常但限速不掉（实测排查记录 2026-08）

**背景：** 广西电信家宽，外网访问家里 NAS 上行被限 ~5M，speedtest.cn 上行能跑满。nf_deaf 规则修复后注入包持续产生（TTL=3，验证通过），但**限速纹丝不动**。以下为完整排查结论，避免后人重蹈。

### 结论（按证据强度排序）

| 证据 | 结论 |
|---|---|
| 外网设备 iperf3 `-R` 单连接稳定 5M | 上行被限 5M |
| 外网设备 iperf3 `-R -P 10` 十并发**总和仍 5M**（多数连接全程 0） | ❌ 不是"限连接数"（否则并发能堆上去） |
| iperf3 单连接 30 秒 **Retr 449 次** | 超速包被直接丢弃 + TCP 重传 = **令牌桶带宽整形（rate policing）** 特征，不是"识别后放行/丢弃"的 DPI |
| 域名含 `speedtest` 的真实 HTTPS 访问 NAS 仍 5M | ❌ DPI **不看 SNI/Host** |
| IPv6 访问同样被限 | 全栈限速，非 IPv4 专属 |
| 注入包（SNI=speedtest.cn / 百度网盘上传请求）目的端口 = 外网设备随机端口 | nf_deaf 注入包**复制真实连接端口**，永远不是白名单端口 443/8080 |

**判定模型：** 运营商对"**白名单之外的目的 IP**"的出站流量做整体带宽整形。speedtest.cn 能跑满只是因为该目标 IP 在白名单内。

### 为什么 nf_deaf 对此线路无效（原理性）

nf_deaf 伪装的是 **SNI/Host**，但：
1. 真实流量目的 IP 是外网设备（永不在白名单），伪装包改变不了这一点
2. 注入包目的端口复制真实连接（随机高位端口），不可能命中 443/8080 白名单端口
3. 整形（丢弃+重传）与"识别内容后限速"不同，注入包内容再逼真也不影响整形器

**判据（30 秒判断 nf_deaf 对你是否有用）：** 外网设备 `iperf3 -c <WAN_IP> -t 30 -R -P 10`。若并发总和与单连接一样 → 整形限速，nf_deaf 无效；若并发明显更高 → 连接数限制，nf_deaf 无效但可考虑 FakeHTTP。

### 验证 nf_deaf 注入机制是否正常（已修复）

对照实验（同一环境唯一变量）：

| 规则 | 注入包 |
|---|---|
| `ct mark set 0xDEA10103 meta mark set 0xDEA10103`（旧） | ❌ 0 个（ct mark 使 packet mark 失效，Linux 6.12/nftables 1.x 实测） |
| `meta mark set 0xDEA10103`（当前，v29 起） | ✅ 每个数据段持续注入 TTL=3 包 |

```bash
# 现场验证注入（iperf3 测速时同时抓包）：
timeout 25 tcpdump -i pppoe-wan -nn -c 20 'ip[8] == 3'
# 预期：源端口 5201/37073 的 length 73（SNI 特征）或 104/872（HTTP 特征）TTL=3 包

# 写入自定义 payload（OpenWrt 无 xxd，用 sed+printf）：
printf '%b' "$(echo -n '<hex>' | sed 's/../\x&/g')" > /sys/kernel/debug/nf_deaf/buf
```

### 可行出路

1. **VPS 隧道（唯一确定性方案）**：外网设备 → VPS:443 → 家里主动出站连 VPS。运营商对 OpenVPN/裸 VLESS 实测不限制，且该方向是出站、目的 IP 可控（VPS），正适合 nf_deaf 类工具。
2. **FakeHTTP（社区验证，适合"纯 host/SNI 模式无效"的线路）**：`MikeWang000000/FakeHTTP` v0.9.18 有 arm64 版。用 tcpdump 抓取**真实测速/网盘上传请求**保存为 bin，`./fakehttp -b xxx.bin -i pppoe-wan`。前提：确认目标（如百度网盘）本身在白名单内（真实上传能跑满），否则 payload 无意义。
3. **查套餐上行带宽**：若套餐上行本来就是 5M（iperf3 测出的就是带宽上限），任何伪装方案均无效，只能找运营商升级。

### 常见坑（本次踩过）

- OpenWrt 无 `xxd`/`od`：切换 payload 用 `printf '%b' "$(echo -n '<hex>' | sed 's/../\x&/g')"`
- nft 输入用 `gt` 不是 `>`（`>` 只是输出渲染）
- PPPoE 拨号出口接口是 `pppoe-wan`，不是 `eth1`
- `tcpdump 'ip[8] == 3'` 抓的是 IPv4 TTL=3 注入包；tcpdump 用 `timeout 25`（10 秒太短，背景注入 0.05 秒就能抓满）
