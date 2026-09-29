# 10Wrt — OpenWrt 固件云编译

[![Build x86/64](https://github.com/zdabing/10Wrt/actions/workflows/build-x86.yml/badge.svg)](https://github.com/zdabing/10Wrt/actions/workflows/build-x86.yml)
[![Build R5C](https://github.com/zdabing/10Wrt/actions/workflows/build-r5c.yml/badge.svg)](https://github.com/zdabing/10Wrt/actions/workflows/build-r5c.yml)

基于 [OpenWrt openwrt-25.12](https://github.com/openwrt/openwrt/tree/openwrt-25.12) 分支源码，使用 GitHub Actions 自动编译 x86/64 和 NanoPi R5C 固件。

两个构建工作流默认使用 `openwrt-25.12` 分支，也可以在手动运行时修改 OpenWrt 源码分支。

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
| **luci-app-oxidns** | OxiDNS 高性能可编程 DNS 引擎（Rust） | [hahaher123/luci-app-oxidns](https://github.com/hahaher123/luci-app-oxidns) |
| **luci-app-ddns** | 动态域名解析 | |
| **luci-app-upnp** | UPnP IGD / NAT-PMP | |
| **luci-app-wol** | 网络唤醒 | |
| **luci-app-ttyd** | 网页终端 | |
| **luci-app-librespeed** | LibreSpeed 测速客户端：路由器主动测指定测速服务器，支持定时任务与历史记录（界面为英文，上游暂无中文翻译） | 官方 feed（luci + packages） |
| **luci-app-firewall** | 防火墙管理 | |
| **luci-theme-round** | Round 主题（默认）：圆角青色玻璃 UI、明暗切换、侧栏布局 | [CyL-Cly/luci-theme-round](https://github.com/CyL-Cly/luci-theme-round) |

#### 网络工具

- `dnsmasq-full` (含 ipset 支持)
- `firewall4` (nftables)
- `curl` / `wget` / `bind-dig`
- `ip-full` / `iperf3` / `tcpdump` / `traceroute` / `ethtool` / `irqbalance`
- `librespeed-cli`（Go 版命令行测速，luci-app-librespeed 的后端）

#### DDNS 支持

- 阿里云 / Cloudflare / DNSPod / 通用服务

#### 内核加速

- **FullCone NAT** — 游戏/P2P 优化
- **BBR** 拥塞控制算法
- **TPROXY** 透明代理支持
- **TUN** 虚拟网卡（VPN/代理需要）
- **veth** 虚拟网卡（LAN 入口旁路自测需要）
- **nft-queue** 内核模块（供使用 NFQUEUE 的程序处理数据包）

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
3. 点击 **Run workflow** → 选择配置仓库分支（如 `dev/main`）→ 在 **OpenWrt 源码分支** 输入框中确认或修改版本（默认 `openwrt-25.12`）→ 点击 **Run workflow**

**方式二：推送代码自动触发**
- 如需推送触发，在 workflow 文件中添加 `push` 触发器即可

**方式三：定时触发**
- 如需定时触发，在 workflow 文件中添加 `schedule` 触发器即可

### 3. 下载固件

编译完成后（约 1-3 小时），在 Actions 运行页面找到 **Upload firmware** 步骤的构件（Artifacts），下载 `.img.gz` 文件。

正式版本会发布到 **Releases** 页面，除镜像外还附带三类记录文件：

Zen Traffic 和 Quickfile 暂时停用，本次固件不会包含它们。

| 文件 | 说明 |
|---|---|
| `SHA256SUMS` | 镜像校验值，下载后可用 `sha256sum -c SHA256SUMS` 核对完整性 |
| `10wrt-packages.manifest` | 固件内已安装软件包及版本清单 |
| `10wrt-sources.tsv` | 本次构建使用的 OpenWrt、feeds 及第三方插件源码提交号 |

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
│       └── mijia-bypass-test.sh              # LAN 入口旁路自测
├── scripts/
│   ├── build-target-env.sh                   # 设备构建参数（目标/种子/设备符号/缓存 key）
│   ├── create-build-records.sh               # 生成 SHA256SUMS / 包清单 / 源码版本记录
│   └── validate-seed-packages.sh             # seed 与 .config 软件包核对
├── .github/workflows/build-common.yml        # 公共构建工作流（编译/验证/发布）
├── .github/workflows/build-r5c.yml           # R5C 入口工作流（调用公共工作流）
├── .github/workflows/build-x86.yml           # x86/64 入口工作流（调用公共工作流）
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
- [hahaher123/luci-app-oxidns](https://github.com/hahaher123/luci-app-oxidns) — OxiDNS LuCI 管理界面
- [CyL-Cly/luci-theme-round](https://github.com/CyL-Cly/luci-theme-round) — Round 主题（默认）
- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)
- [SuLingGG/OpenWrt-Rpi](https://github.com/SuLingGG/OpenWrt-Rpi)

## 免责声明

本固件仅供学习研究使用，请勿用于任何商业用途。使用本固件所导致的任何损失由使用者自行承担。
