# 10Wrt — OpenWrt 固件云编译

[![Build x86/64](https://github.com/zdabing/10Wrt/actions/workflows/build-x86.yml/badge.svg)](https://github.com/zdabing/10Wrt/actions/workflows/build-x86.yml)
[![Build R5C](https://github.com/zdabing/10Wrt/actions/workflows/build-r5c.yml/badge.svg)](https://github.com/zdabing/10Wrt/actions/workflows/build-r5c.yml)

基于 [OpenWrt](https://github.com/openwrt/openwrt) 源码，使用 GitHub Actions 自动编译 x86/64 和 NanoPi R5C 固件。

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
| **luci-app-clashoo** | Clashoo 双内核代理（mihomo + sing-box） | [kenzok8/openwrt-clashoo](https://github.com/kenzok8/openwrt-clashoo) |
| **luci-app-oxidns** | OxiDNS 高性能可编程 DNS 引擎（Rust） | [svenshi/luci-app-oxidns](https://github.com/svenshi/luci-app-oxidns) |
| **luci-app-ddns** | 动态域名解析 | |
| **luci-app-upnp** | UPnP IGD / NAT-PMP | |
| **luci-app-bandix** | 带宽监控 | [timsaya/luci-app-bandix](https://github.com/timsaya/luci-app-bandix) |
| **luci-app-wol** | 网络唤醒 | |
| **luci-app-quickfile** | 文件管理器 | [sbwml/luci-app-quickfile](https://github.com/sbwml/luci-app-quickfile) |
| **luci-app-ttyd** | 网页终端 | |
| **luci-app-firewall** | 防火墙管理 | |
| **luci-theme-round** | Round 主题（默认）：圆角青色玻璃 UI、明暗切换、侧栏布局 | [CyL-Cly/luci-theme-round](https://github.com/CyL-Cly/luci-theme-round) |

#### 网络工具

- `dnsmasq-full` (含 ipset 支持)
- `firewall4` (nftables)
- `curl` / `wget` / `bind-dig`
- `ip-full` / `iperf3` / `tcpdump` / `traceroute` / `ethtool` / `irqbalance`

#### DDNS 支持

- 阿里云 / Cloudflare / DNSPod / 通用服务

#### 内核加速

- **FullCone NAT** — 游戏/P2P 优化
- **BBR** 拥塞控制算法
- **TPROXY** 透明代理支持
- **TUN** 虚拟网卡（VPN/代理需要）
- **veth** / **nft-queue** / **nft-nat**（LAN 入口旁路自测、Open-Box 的 `auto_redirect` 需要）

#### 系统工具

- `bash` / `vim` / `jq` / `htop`
- `openssh-sftp-server`
- `zram-swap`（内存压缩交换）
- `ca-certificates`（HTTPS 证书）
- `blockdev` / `fdisk` / `lsblk`（磁盘工具，x86 额外含 `parted`）

### 首次启动自动配置

- 开启 **Packet Steering**（多队列软中断均衡）
- 时区设为 `Asia/Shanghai`
- Luci 诊断地址改百度
- 启动小米 CDN 坏节点规避（`/root/mijia-guard.sh`，之后每 15 分钟由 cron 接管）

### 小米 CDN 坏节点规避

小米 CDN 池里混有「80 端口静默丢弃 SYN」的节点，米家 App 拿到这种 IP 会卡在设备页。
固件内置 `/root/mijia-guard.sh`，每 15 分钟体检一次节点池，做两件事：

1. 把 `api.io.mi.com` / `ot.io.mi.com` 钉定到健康 IP（写 `/etc/hosts`，自愈更新）
2. nft DNAT 兜底：LAN 发往坏节点 80 端口的连接改道到健康节点，
   覆盖 App 走 HTTPDNS 绕过路由器 DNS 的情况

注意 `10.0.0.1` 的管理地址不受影响；体检日志在 `/root/mijia-guard.log`。

### 验证旁路是否真的生效

旁路规则是 `iifname "br-lan"` 上的 prerouting DNAT，**只有从 LAN 口进来的包才会命中**，
所以从路由器本机 `curl` 坏节点是验不出来的（本机流量走 OUTPUT，不经过 LAN 入口，命中计数永远是 0）。

正确做法是让一台 LAN 侧机器发起请求，固件内置的 `/root/mijia-bypass-test.sh` 会自动完成这件事：
用 veth + network namespace 造一台假 LAN 客户端挂进 `br-lan`，先跑对照组（直连健康节点，
证明测试通路本身是通的），再拿坏节点做主探针，用规则计数增量 + HTTP 响应 + conntrack 三重取证。

```sh
/root/mijia-bypass-test.sh        # 退出码 0=命中 1=未命中 2=环境不具备(未测) 3=当前无坏节点
/root/mijia-bypass-test.sh -v     # 附带原始证据
/root/mijia-bypass-test.sh -m     # 只打印手工验证步骤（找台 LAN 里的 PC 自己 curl）
```

内核需要 `kmod-veth`（已并入 `configs/*.seed`）。缺它时脚本会报「未测」并列出手工步骤，
**不会退回回环测试** —— 那条路径不经过 LAN 入口，测出来的"成功"是假阳性。

### Open-Box（内置一键安装）

[Open-Box](https://github.com/liandu2024/Open-Box) 是一体化透明代理面板：装完用浏览器就能配订阅、节点、
分流、DNS 和防火墙，自带 sing-box 内核、Node 运行时和完整 GeoSite / GeoIP 数据，不用手写配置文件。

完整包约 100MB，所以固件不预装，而是把上游 `v0.1.196` 的安装脚本固化进 `/root/open-box/`，
内核侧依赖全部编进固件，刷完 SSH 一条命令就能装：

```sh
sh /root/open-box/install.sh --mirror   # 走镜像加速下载；直连 GitHub 顺畅就去掉 --mirror
sh /root/open-box/update.sh             # 升级，保留订阅与配置
sh /root/open-box/uninstall.sh          # 卸载
```

装完面板在 `http://<路由器IP>:2026`，首次访问设置管理密码。

- 安装器的依赖自检会全过：`kmod-tun`、`kmod-nft-queue`、`kmod-nft-nat`（fw4 自带）、
  `kmod-veth`、`ip-full`、CA 证书都已内置，不会再走 apk 补装
- 安装脚本要求 `/opt` 所在分区有 **≥512MB 空闲**、内存 ≥512MB，
  所以两个 seed 的 `CONFIG_TARGET_ROOTFS_PARTSIZE` 都是 1024
- **别和已内置的 luci-app-clashoo 同时启用**：两者都要接管 DNS 和防火墙透明代理，会互相抢；
  Open-Box 自带的冲突检测只认 openclash / nikki / passwall / homeproxy，认不出 clashoo
- 固化的副本只用于首次安装；面板内的「检查更新」走的是上游 `update.sh`（也在 `/root/open-box/`）。
  要跟上游同步脚本本体，重新拉一份覆盖这个目录即可：
  `curl -fsSL https://raw.githubusercontent.com/liandu2024/Open-Box/main/scripts/install.sh -o files/root/open-box/install.sh`

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
gunzip openwrt-*-x86-64-generic-ext4-combined-efi.img.gz

# 写入 U 盘或硬盘（替换 /dev/sdX 为实际设备）
dd if=openwrt-*-x86-64-generic-ext4-combined-efi.img of=/dev/sdX bs=4M status=progress
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
│   ├── etc/uci-defaults/99-init-settings     # 首次启动脚本
│   └── root/
│       ├── mijia-guard.sh                    # 小米 CDN 坏节点体检与规避
│       ├── mijia-bypass-test.sh              # LAN 入口旁路自测
│       └── open-box/                         # Open-Box 安装/升级/卸载脚本（上游 v0.1.196）
├── .github/workflows/build-r5c.yml           # R5C 工作流
├── .github/workflows/build-x86.yml           # x86/64 工作流
```

### 自定义修改

1. **修改种子配置** — 编辑 `configs/*.seed`，添加/移除软件包
2. **修改自定义脚本** — 编辑 `diy.sh`，可添加 feed、修改默认 IP、打补丁等
3. **修改首次启动设置** — 编辑 `files/etc/uci-defaults/99-init-settings`

---

## 致谢

- [OpenWrt](https://github.com/openwrt/openwrt)
- [xuanranran/OpenWrt_RockChip](https://github.com/xuanranran/OpenWrt_RockChip) — 参考项目
- [kenzok8/openwrt-clashoo](https://github.com/kenzok8/openwrt-clashoo) — Clashoo 双内核代理（mihomo + sing-box）
- [nikkinikki-org/OpenWrt-nikki](https://github.com/nikkinikki-org/OpenWrt-nikki) — Nikki 代理客户端
- [sbwml](https://github.com/sbwml) — 多个插件包
- [svenshi/luci-app-oxidns](https://github.com/svenshi/luci-app-oxidns) — OxiDNS LuCI 管理界面
- [timsaya/luci-app-bandix](https://github.com/timsaya/luci-app-bandix) — 带宽监控
- [CyL-Cly/luci-theme-round](https://github.com/CyL-Cly/luci-theme-round) — Round 主题（默认）
- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)
- [SuLingGG/OpenWrt-Rpi](https://github.com/SuLingGG/OpenWrt-Rpi)

## 免责声明

本固件仅供学习研究使用，请勿用于任何商业用途。使用本固件所导致的任何损失由使用者自行承担。
