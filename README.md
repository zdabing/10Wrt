# 10Wrt — ImmortalWrt 固件云编译

[![Build x86/64](https://github.com/zdabing/10Wrt/actions/workflows/build-x86.yml/badge.svg)](https://github.com/zdabing/10Wrt/actions/workflows/build-x86.yml)
[![Build R5C](https://github.com/zdabing/10Wrt/actions/workflows/build-r5c.yml/badge.svg)](https://github.com/zdabing/10Wrt/actions/workflows/build-r5c.yml)

基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) 源码，使用 GitHub Actions 自动编译 x86/64 和 NanoPi R5C 固件。

管理地址: **http://10.0.0.1**

## 固件特性

### 支持设备

| 目标 | 架构 | 用途 |
|---|---|---|
| **x86/64** | AMD64 | 软路由 / 虚拟机 / PC |
| **NanoPi R5C** | Rockchip RK3568 | 友善 NanoPi R5C |

### 管理地址

```
管理地址: http://10.0.0.1
用户名:   root
密码:     (首次登录自行设置)
```

### 预装软件

#### Luci 插件

| 插件 | 说明 | 来源 |
|---|---|---|
| **luci-app-homeproxy** | HomeProxy 代理客户端 | [immortalwrt/homeproxy](https://github.com/immortalwrt/homeproxy) |
| **luci-app-clashoo** | Clashoo 双内核代理（mihomo + sing-box） | [kenzok8/openwrt-clashoo](https://github.com/kenzok8/openwrt-clashoo) |
| **luci-app-miclash** | MiClash Clash 代理客户端 | [ang3el7z/luci-app-miclash](https://github.com/ang3el7z/luci-app-miclash) |
| **luci-app-mosdns** | MosDNS DNS 处理/分流 | [sbwml/luci-app-mosdns](https://github.com/sbwml/luci-app-mosdns) |
| **luci-app-oxidns** | OxiDNS 高性能可编程 DNS 引擎（Rust） | [svenshi/luci-app-oxidns](https://github.com/svenshi/luci-app-oxidns) |
| **luci-app-oaf** | 应用过滤 | |
| **luci-app-ddns** | 动态域名解析 | |
| **luci-app-upnp** | UPnP IGD / NAT-PMP | |
| **luci-app-3cat** | 3Cat 工具 | |
| **luci-app-bandix** | 带宽监控 | [timsaya/luci-app-bandix](https://github.com/timsaya/luci-app-bandix) |
| **luci-app-onliner** | 在线设备列表 | |
| **luci-app-wol** | 网络唤醒 | |
| **luci-app-quickfile** | 文件管理器 | [sbwml/luci-app-quickfile](https://github.com/sbwml/luci-app-quickfile) |
| **luci-app-ttyd** | 网页终端 | |
| **luci-app-firewall** | 防火墙管理 | |
| **luci-app-status** | 状态监控 | |
| **luci-app-opkg** | 软件包管理 | |
| **luci-theme-aurora** | Aurora 主题（默认） | [eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora) |

#### 网络工具

- `dnsmasq-full` (含 ipset 支持)
- `firewall4` (nftables)
- `iptables` / `ip6tables`
- `curl` / `wget` / `bind-dig`
- `ip-full` / `iperf3` / `tcpdump` / `traceroute`

#### DDNS 支持

- 阿里云 / Cloudflare / DNSPod / 通用服务

#### 内核加速

- **FullCone NAT** — 游戏/P2P 优化
- **BBR** 拥塞控制算法
- **TPROXY** 透明代理支持
- **IPv6 NAT** 支持
- **TUN** 虚拟网卡（VPN/代理需要）
- **nf_deaf** — 绕过运营商 DPI 限速（默认启用，见下方说明）

### nf_deaf：绕过运营商 DPI 限速

**解决的问题**：运营商对非白名单出向 TCP 流量做 DPI 限速（典型现象：外网访问 NAS 上行只有 5M，而 speedtest.cn 测速上行能跑满——测速站点在白名单内）。江苏联通等联通系宽带是重灾区（详见 V2EX [t/1210042](https://www.v2ex.com/t/1210042)）。

**原理**：nf_deaf 内核模块在 TCP 连接早期抢先注入一个伪装成测速请求的包，TTL=3 仅到达运营商 DPI、TCP 校验和故意错误远端收不到。DPI 误判该连接为测速流量后不再限速。来源：[kmb21y66/nf_deaf](https://github.com/kmb21y66/nf_deaf)（[kob/nf_deaf-openwrt](https://github.com/kob/nf_deaf-openwrt) 打包）。

**默认行为**：对所有公网 IPv4 出向 TCP 大包生效，同一连接每个数据段持续注入（无连接级去重），私有/保留地址自动跳过。IPv6 不参与。

**⚠️ 已知问题（v29 已修复）**：早期打标规则用 `ct mark set 0xDEA10103 meta mark set 0xDEA10103`（先 ct mark 再 packet mark）实现每连接只注入一次的去重。实测在 nftables 1.x / Linux 6.12 下，同一条规则里 `ct mark set` 会导致 `meta mark set` 失效——注入完全不触发（流量过链、WAN 口无 TTL=3 包）。已移除 `ct mark set` 改为仅 `meta mark set`：同一连接每个数据段注入一次（每 ~1500 字节数据包附加 104 字节伪装包，约 7% 出向开销），对 DPI 反而持续维持"测速流量"外观。

**Mark 说明**（规则见 `files/etc/nftables.d/10-nf-deaf.nft`）：mark `0xDEA10103` = Magic `0xDEA` + 错误校验和(bit16) + 延迟 1 jiffy(bit8) + TTL=3(bit0-7)。

**注入特征两种可选**（运行时切换，无需重刷固件）：
- 明文 HTTP `Host` 特征（默认）：`GET / HTTP/1.1 Host: www.speedtest.cn`，适合移动/按 Host 匹配的 DPI（V2EX [t/1118730](https://www.v2ex.com/t/1118730)）
- TLS SNI 特征：完整伪造的 TLS ClientHello，SNI=`speedtest.cn`，适合联通系 DPI（HTTPS 按 SNI 匹配白名单，见下文 t/1210042）

**验证是否生效**：
```bash
lsmod | grep nf_deaf                          # 模块已加载
nft list chain inet fw4 nf_deaf_postrouting   # 打标规则存在
# 抓包确认握手后出现 TTL=3 的注入包：
tcpdump -i wan -nn 'tcp port 80 and ip[8] == 3' -c 20
```

**自定义**：
- 排除某个 IP（如代理节点）：在 `/etc/nftables.d/10-nf-deaf.nft` 的 `ip daddr {...} return` 行前加 `ip daddr <IP> return`
- 切换注入特征（写入 `/sys/kernel/debug/nf_deaf/buf`）：
  - 明文 HTTP `Host` 特征：
    ```bash
    printf 'GET / HTTP/1.1\r\nHost: www.speedtest.cn\r\n\r\n' > /sys/kernel/debug/nf_deaf/buf
    ```
  - TLS SNI 特征（联通系 DPI 适用，SNI=`speedtest.cn`）：
    ```bash
    echo -n '1603010044010000400303000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f00000413011302010000130000000f00000c7370656564746573742e636e' | xxd -r -p > /sys/kernel/debug/nf_deaf/buf
    ```
- 整体关闭：`rmmod nf_deaf`（`modprobe nf_deaf` 重新开启）

---

### 已知的绕过方案对比（江苏联通实测参考）

来源：V2EX [t/1210042](https://www.v2ex.com/t/1210042)（上海联通，江苏联通同属联通系 DPI）

| 方案 | 效果 | 说明 |
|---|---|---|
| **IPv6 直连** ⭐ | **不限速** | WAN 口 IPv6 地址不受限。外网访问 NAS 走 IPv6（DDNS AAAA 记录 / Tailscale）即可跑满上行，无需任何伪装 |
| TLS SNI 白名单 | 443/8080 端口 + SNI 含 `speedtest` 可绕过 | 对应上方 nf_deaf 的 SNI 特征注入 |
| OpenVPN / 裸 VLESS | 未被限速 | 协议特征不在 DPI 限速集内，走这类隧道可绕开 |
| WireGuard / VMESS-AES | 被限到 5M | 特征命中 DPI 限速集，无效 |
| fakehttp / fakesip | 已失效 | 社区反馈当前版本不适用 |

**结论**：有公网 IPv6 时优先走 IPv6 直连（零开销、最可靠）；nf_deaf 作为 IPv4 场景的兜底方案，联通系 DPI 建议用上方 TLS SNI 特征。

#### 系统工具

- `bash` / `vim` / `jq` / `htop` / `nano`
- GNU coreutils + procps-ng（完整版工具链）
- `openssh-sftp-server`
- `zram-swap`（内存压缩交换）
- `ca-certificates`（HTTPS 证书）

### 首次启动自动配置

- 开启 **Packet Steering**（多队列软中断均衡）
- 时区设为 `Asia/Shanghai`
- Luci 诊断地址改百度

---

## 使用方法

### 1. Fork 或推送此仓库

```bash
git clone https://github.com/YOUR_USERNAME/10Wrt.git
cd 10Wrt
# 根据需求修改 configs/ 下的种子配置
git push
```

### 2. 触发编译

**方式一：手动触发**
1. 打开 GitHub 仓库 → **Actions** 标签
2. 选择 **Build NanoPi R5C** 或 **Build x86/64**
3. 点击 **Run workflow** → 选择分支 → 点击 **Run**

**方式二：推送代码自动触发**
- 如需推送触发，在 workflow 文件中添加 `push` 触发器即可

**方式三：定时触发**
- 如需定时触发，在 workflow 文件中添加 `schedule` 触发器即可

### 3. 下载固件

编译完成后（约 1-3 小时），在 Actions 运行页面找到 **Upload firmware** 步骤的构件（Artifacts），下载 `.img.gz` 文件。

### x86/64 刷机

```bash
# 解压
gunzip immortalwrt-*-x86-64-generic-ext4-combined-efi.img.gz

# 写入 U 盘或硬盘（替换 /dev/sdX 为实际设备）
dd if=immortalwrt-*-x86-64-generic-ext4-combined-efi.img of=/dev/sdX bs=4M status=progress
```

### NanoPi R5C 刷机

解压 `*friendlyarm_nanopi-r5c-squashfs-sysupgrade.img.gz`，使用 `dd` 或 balenaEtcher 写入 MicroSD 卡/TF 卡。

---

## 项目结构

```
├── diy.sh                                    # 自定义配置脚本
├── configs/
│   ├── x86_64.seed                           # x86/64 种子配置
│   └── r5c.seed                              # NanoPi R5C 种子配置
├── files/
│   └── etc/uci-defaults/99-init-settings     # 首次启动脚本
├── .github/workflows/build-r5c.yml           # R5C 工作流
├── .github/workflows/build-x86.yml           # x86/64 工作流
```

### 自定义修改

1. **修改种子配置** — 编辑 `configs/*.seed`，添加/移除软件包
2. **修改自定义脚本** — 编辑 `diy.sh`，可添加 feed、修改默认 IP、打补丁等
3. **修改首次启动设置** — 编辑 `files/etc/uci-defaults/99-init-settings`

---

## 致谢

- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
- [xuanranran/OpenWrt_RockChip](https://github.com/xuanranran/OpenWrt_RockChip) — 参考项目
- [kenzok8/openwrt-clashoo](https://github.com/kenzok8/openwrt-clashoo) — Clashoo 双内核代理（mihomo + sing-box）
- [ang3el7z/luci-app-miclash](https://github.com/ang3el7z/luci-app-miclash) — MiClash Clash 代理客户端
- [nikkinikki-org/OpenWrt-nikki](https://github.com/nikkinikki-org/OpenWrt-nikki) — Nikki 代理客户端
- [sbwml](https://github.com/sbwml) — 多个插件包
- [svenshi/luci-app-oxidns](https://github.com/svenshi/luci-app-oxidns) — OxiDNS LuCI 管理界面
- [timsaya/luci-app-bandix](https://github.com/timsaya/luci-app-bandix) — 带宽监控
- [eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora) — Aurora 主题（默认）
- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)
- [SuLingGG/OpenWrt-Rpi](https://github.com/SuLingGG/OpenWrt-Rpi)

## 免责声明

本固件仅供学习研究使用，请勿用于任何商业用途。使用本固件所导致的任何损失由使用者自行承担。
