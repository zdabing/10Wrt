# 10Wrt — ImmortalWrt 固件云编译

[![Build x86/64](https://github.com/zdabing/10Wrt/actions/workflows/build-x86.yml/badge.svg)](https://github.com/zdabing/10Wrt/actions/workflows/build-x86.yml)
[![Build R5C](https://github.com/zdabing/10Wrt/actions/workflows/build-r5c.yml/badge.svg)](https://github.com/zdabing/10Wrt/actions/workflows/build-r5c.yml)

基于 [fanchmwrt](https://github.com/fanchmwrt/fanchmwrt) 源码（OpenWrt 主线 fork，内置 fwx 流量识别体系），使用 GitHub Actions 自动编译 x86/64 和 NanoPi R5C 固件。

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
| **luci-app-wol** | 网络唤醒 | |
| **luci-app-quickfile** | 文件管理器 | [sbwml/luci-app-quickfile](https://github.com/sbwml/luci-app-quickfile) |
| **luci-app-fwx-dashboard** | fwx 实时流量/应用统计看板 | [fanchmwrt/fanchmwrt-packages](https://github.com/fanchmwrt/fanchmwrt-packages) |
| **luci-app-fwx-appfilter** | fwx 应用识别/管控（特征库） | [fanchmwrt/fanchmwrt-packages](https://github.com/fanchmwrt/fanchmwrt-packages) |
| **luci-app-fwx-session-stat** | fwx 会话/流量统计 | [fanchmwrt/fanchmwrt-packages](https://github.com/fanchmwrt/fanchmwrt-packages) |
| **luci-app-fwx-\*（全家桶 11 个）** | 上网管控 / 行为记录 / 用户管理 / 系统设置 / App 中心 | [fanchmwrt/fanchmwrt-packages](https://github.com/fanchmwrt/fanchmwrt-packages) |
| **luci-app-ttyd** | 网页终端 | |
| **luci-app-firewall** | 防火墙管理 | |
| **luci-theme-liquid** | Liquid 主题（默认） | [zzsj0928/luci-theme-liquid](https://github.com/zzsj0928/luci-theme-liquid) |

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

#### 流量识别（fwx，来自 fanchmwrt）

- 基于 fanchmwrt 的 fwx 内核模块 + fwxd 守护进程，提供**实时流量看板、应用识别（应用防火墙）、会话统计**，并**内置 fwx 全家桶**：上网管控（MAC 过滤/黑名单）、上网行为记录（含白名单/用户记录）、用户管理、系统与网络设置、看板自定义、App 中心
- 预装应用特征库（微信/抖音/王者荣耀/原神等 200+ 应用），可通过 **luci-app-fwx-feature** 在线升级特征
- ⚠️ **版权声明**：应用特征库 feature.cfg 版权归 destan19/fanchmwrt，个人免费使用、**禁止商用**；fwx 后端（kmod-fwx/fwxd）与 LuCI 前端为 GPL-2.0 / Apache-2.0

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
- [nikkinikki-org/OpenWrt-nikki](https://github.com/nikkinikki-org/OpenWrt-nikki) — Nikki 代理客户端
- [sbwml](https://github.com/sbwml) — 多个插件包
- [svenshi/luci-app-oxidns](https://github.com/svenshi/luci-app-oxidns) — OxiDNS LuCI 管理界面
- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)
- [SuLingGG/OpenWrt-Rpi](https://github.com/SuLingGG/OpenWrt-Rpi)

## 免责声明

本固件仅供学习研究使用，请勿用于任何商业用途。使用本固件所导致的任何损失由使用者自行承担。
