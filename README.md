# 10Wrt — ImmortalWrt 固件云编译

[![Build x86/64](https://github.com/zdabing/10Wrt/actions/workflows/build-x86.yml/badge.svg)](https://github.com/zdabing/10Wrt/actions/workflows/build-x86.yml)
[![Build R5C](https://github.com/zdabing/10Wrt/actions/workflows/build-r5c.yml/badge.svg)](https://github.com/zdabing/10Wrt/actions/workflows/build-r5c.yml)

基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) 源码，使用 GitHub Actions 自动编译 x86/64 和 NanoPi R5C 固件。

配置仓库分支：[`main`](https://github.com/zdabing/10Wrt/tree/main)（默认）编译 ImmortalWrt；[`openwrt`](https://github.com/zdabing/10Wrt/tree/openwrt) 编译 OpenWrt。
下载请优先打开 [最新发布](https://github.com/zdabing/10Wrt/releases/latest)，并核对标题中的设备和源码类型；[全部发布](https://github.com/zdabing/10Wrt/releases) 包含历史版本。
ImmortalWrt 新发布统一使用 `v年.月.日-t时分秒-immortalwrt-设备-构建编号-重试编号` 标签，例如 `v2026.10.6-t014347-immortalwrt-r5c-73-1`。
标签名和标题采用构建完成时间（UTC+8），包含设备及构建编号；由 Release 发布流程直接创建标签，指向实际配置源码提交，使用默认 `GITHUB_TOKEN`。发布说明链接到对应 Actions 构建，旧版本按 Release 发布时间清理，使用 `--latest` 指定最新发布。
各源码、各设备分别保留最新 7 个版本，清理同时识别新旧标签；已有发布和下载链接保持不变。OpenWrt 分支的发布规则由该分支维护。

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
| **luci-app-bettbox** | Bettbox 代理管理（内置 `bettbox` 核心与 `bettbox-forge` 脚本引擎） | [zdabing/Z_bett](https://github.com/zdabing/Z_bett) |
| **luci-app-ddns** | 动态域名解析 | |
| **luci-app-upnp** | UPnP IGD / NAT-PMP | |
| **luci-app-3cat** | 3Cat 工具 | |
| **luci-app-wol** | 网络唤醒 | |
| **luci-app-ttyd** | 网页终端 | |
| **luci-app-firewall** | 防火墙管理 | |
| **luci-app-zen** | Zen 主题与流量分析控制台（默认主题）：首页仪表盘、明暗切换、响应式侧栏、历史用量及通知 | [zdabing/luci-zen](https://github.com/zdabing/luci-zen) |
| **luci-zen** | Zen Rust/eBPF 流量统计与识别后端（提供 `zen-traffic` 服务） | [zdabing/luci-zen](https://github.com/zdabing/luci-zen) |
| **luci-theme-bootstrap** | Bootstrap 备用主题 | |

x86/64 与 NanoPi R5C 均集成 Zen 的主题、流量后端和 LuCI 应用，默认使用 Zen。
流量后端及所需内核模块由 Zen 软件包的依赖自动选择，
可在“状态 → Zen 流量”页面查看统计。

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

#### 系统工具

- `bash` / `vim` / `jq` / `htop`
- `openssh-sftp-server`
- `zram-swap`（内存压缩交换）
- `ca-certificates`（HTTPS 证书）
- `blockdev` / `fdisk` / `lsblk`（磁盘工具，x86 额外含 `parted`）

### 脚本与诊断兼容

两种设备明确启用 BusyBox 的小数秒 `sleep`、`timeout`、`flock`、`stat -c`、完整 `nslookup`，以及支持 UDP、端口探测和超时的 `nc`（`-u/-z/-w`）。`nc` 使用 1.10 兼容实现，不再提供旧实现的 `-f FILE` 扩展。

预装 `gzip`、`coreutils-sha256sum`、`yq`、`unzip`、ucode 的文件系统／UCI 模块和匹配内核的 `kmod-nft-socket`，满足插件下载校验、配置转换与诊断所需的实际包依赖。BusyBox 已有同名命令并不能代替 APK 对独立软件包的依赖检查。

构建在 `make defconfig` 后检查功能选项，打包后再检查 BusyBox 的实际编译配置和固件软件包清单；任一缺失会停止发布，避免忽略编译错误后产出缺工具的固件。不增加常驻服务。这些设置需重新构建并升级固件才生效，单独更新 Bettbox APK 不会替换系统 BusyBox。

### 首次启动自动配置

- 开启 **Packet Steering**（全核软中断均衡 `packet_steering='2'` + RFS 流亲和 `steering_flows='128'`）
- 默认通过 `etc/sysctl.d/99-10wrt-network.conf` 启用 **TCP BBR** 并调优 socket 缓冲、网卡接收队列及 RFS 流表（用户可在 `/etc/sysctl.conf` 覆盖）
- 默认启用 **irqbalance** 分配硬件中断；R5C 的 ImmortalWrt `kmod-r8125` 默认支持 RSS 与多发送队列。
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
3. 点击 **Run workflow** → 选择 `main` 分支 → 点击 **Run**

Zen 与 Bettbox 源码均使用各自仓库的 `main` 分支。
自有项目 `zdabing/luci-zen` 的两个软件包（`luci-zen` 与 `luci-app-zen`）放在构建树 `package/zen/`，`zdabing/Z_bett` 的 `bettbox` 与 `luci-app-bettbox` 放在 `package/bettbox/`，由构建系统直接扫描。目录名称不作为在线 APK 软件源；不再注册 `new` 或 `kenzok8` feed。

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
│   ├── etc/sysctl.d/99-10wrt-network.conf    # 网络缓冲与 BBR 调优
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
- [nikkinikki-org/OpenWrt-nikki](https://github.com/nikkinikki-org/OpenWrt-nikki) — Nikki 代理客户端
- [sbwml](https://github.com/sbwml) — 多个插件包
- [zdabing/luci-zen](https://github.com/zdabing/luci-zen) — Zen 主题与流量统计
- [zdabing/Z_bett](https://github.com/zdabing/Z_bett) — Bettbox 代理核心与 LuCI 界面
- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)
- [SuLingGG/OpenWrt-Rpi](https://github.com/SuLingGG/OpenWrt-Rpi)

## 免责声明

本固件仅供学习研究使用，请勿用于任何商业用途。使用本固件所导致的任何损失由使用者自行承担。

## Zen eBPF 安装依赖与配套模块

两个目标明确内置 `luci-zen`（提供 `zen-traffic`）、`kmod-sched-bpf`、`kmod-sched-core`。构建会验证选包和实际内核 BPF 能力，缺少配套包时停止发布。

每次固件附带 `zen-support.tar.gz` 和 `zen-support.json`，保留同一构建的目标 APK 软件源、签名公钥、两个 Zen 功能包（`luci-zen`、`luci-app-zen`）及配置/校验清单。该归档只用于对应固件，不能把其他构建的内核模块混装；用户态依赖仍使用匹配软件源。

Zen 签名软件源与安装入口说明：[APK 安装与发布](https://github.com/zdabing/luci-zen/blob/main/docs/APK-DISTRIBUTION.md)。官方 OpenWrt 软件源不自动用于 ImmortalWrt 或其他自编译固件。
