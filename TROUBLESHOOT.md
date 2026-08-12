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

