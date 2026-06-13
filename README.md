# 10Wrt — ImmortalWrt 固件云编译

[![Build ImmortalWrt](https://github.com/YOUR_USERNAME/YOUR_REPO/actions/workflows/build-immortalwrt.yml/badge.svg)](https://github.com/YOUR_USERNAME/YOUR_REPO/actions/workflows/build-immortalwrt.yml)

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

| 插件 | 说明 |
|---|---|
| **luci-app-homeproxy** | HomeProxy 代理客户端 |
| **luci-app-nikki** | Nikki 代理客户端 |
| **luci-app-mosdns** | MosDNS DNS 处理/分流 |
| **luci-app-oaf** | 应用过滤 |
| **luci-app-ddns** | 动态域名解析 |
| **luci-app-upnp** | UPnP IGD / NAT-PMP |
| **luci-app-3cat** | 3Cat 工具 |
| **luci-app-bandix** | 带宽监控 |
| **luci-app-onliner** | 在线设备列表 |
| **luci-app-wol** | 网络唤醒 |
| **luci-app-quickfile** | 文件管理器 |
| **luci-app-ttyd** | 网页终端 |
| **luci-app-firewall** | 防火墙管理 |
| **luci-app-status** | 状态监控 |
| **luci-app-opkg** | 软件包管理 |
| **luci-app-aurora** | Aurora 主题（默认） |

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
2. 选择 **Build ImmortalWrt**
3. 点击 **Run workflow** → 选择分支 → 点击 **Run**

**方式二：推送代码自动触发**
- 推送到 `main` 分支自动开始编译

**方式三：定时触发**
- 每周一凌晨 0:00 自动编译

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
└── .github/workflows/build-immortalwrt.yml   # GitHub Actions 工作流
```

### 自定义修改

1. **修改种子配置** — 编辑 `configs/*.seed`，添加/移除软件包
2. **修改自定义脚本** — 编辑 `diy.sh`，可添加 feed、修改默认 IP、打补丁等
3. **修改首次启动设置** — 编辑 `files/etc/uci-defaults/99-init-settings`

---

## 致谢

- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
- [xuanranran/OpenWrt_RockChip](https://github.com/xuanranran/OpenWrt_RockChip) — 参考项目
- [kenzok8/openwrt-clashoo](https://github.com/kenzok8/openwrt-clashoo)
- [sbwml](https://github.com/sbwml) — 多个插件包
- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)
- [SuLingGG/OpenWrt-Rpi](https://github.com/SuLingGG/OpenWrt-Rpi)

## 免责声明

本固件仅供学习研究使用，请勿用于任何商业用途。使用本固件所导致的任何损失由使用者自行承担。
