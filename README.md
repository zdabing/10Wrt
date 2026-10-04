# 10Wrt — OpenWrt 固件云编译

[![Build x86/64](https://github.com/zdabing/10Wrt/actions/workflows/build-x86.yml/badge.svg)](https://github.com/zdabing/10Wrt/actions/workflows/build-x86.yml)
[![Build R5C](https://github.com/zdabing/10Wrt/actions/workflows/build-r5c.yml/badge.svg)](https://github.com/zdabing/10Wrt/actions/workflows/build-r5c.yml)

基于 [OpenWrt openwrt-25.12](https://github.com/openwrt/openwrt/tree/openwrt-25.12) 分支源码，使用 GitHub Actions 自动编译 x86/64 和 NanoPi R5C 固件。

配置仓库分支：[`openwrt`](https://github.com/zdabing/10Wrt/tree/openwrt) 编译 OpenWrt；[`main`](https://github.com/zdabing/10Wrt/tree/main)（默认）编译 ImmortalWrt。
[Releases](https://github.com/zdabing/10Wrt/releases) 标题按 `10Wrt OpenWrt / ImmortalWrt 设备 — 日期` 区分；新 Tag 使用 `openwrt-` / `immortalwrt-` 前缀，各源码、各设备分别保留最新 7 个版本。

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
| **luci-theme-zen** | Zen 主题（默认）：登录页、首页仪表盘、明暗切换、响应式侧栏 | [zdabing/luci-zen](https://github.com/zdabing/luci-zen) |
| **luci-app-zen-traffic** | 设备流量统计、日/月用量与 WAN 实时历史；内置 `zen-traffic` 后端 | [zdabing/luci-zen](https://github.com/zdabing/luci-zen) |

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
3. 点击 **Run workflow** → 选择配置仓库分支 `openwrt` → 在 **OpenWrt 源码分支** 输入框中确认或修改版本（默认 `openwrt-25.12`）→ 点击 **Run workflow**

R5C 还可选择 **Zen 源码分支或标签**，默认 `main`；验收修复版填
`codex/router-acceptance`。这是 `luci-zen` 仓库的分支，与上方 10Wrt 配置仓库分支
及 OpenWrt 源码分支分别独立。构建记录会保存实际检出的 Zen 提交号。
**发布 Release** 默认关闭：测试时只生成固件 artifact 和耗时记录，不发布或删除
已有 Release/Tag。正式发布时才勾选；x86/64 原有发布行为保持不变。

**方式二：推送代码自动触发**
- 如需推送触发，在 workflow 文件中添加 `push` 触发器即可

**方式三：定时触发**
- 如需定时触发，在 workflow 文件中添加 `schedule` 触发器即可

### 3. 下载固件

编译完成后（约 1-3 小时），在 Actions 运行页面找到 **Upload firmware** 步骤的构件（Artifacts），下载 `.img.gz` 文件。

正式版本会发布到 **Releases** 页面，除镜像外还附带三类记录文件：

x86/64 和 R5C 默认使用 Zen 主题，并内置同一份 `luci-zen` 源码中的
`zen-traffic` 后端、`luci-app-zen-traffic` 应用及 `kmod-sched-core`、
`kmod-sched-bpf` 内核模块。刷入新编译的固件后可使用主题设备统计和
“状态 → Zen 流量”页面。Quickfile 仍暂时停用。

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
│   ├── check-bpf-toolchain.sh                # eBPF 工具链与配置预检查
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

### eBPF 编译依赖检查

工作流安装 LLVM 后会立即检查五个工具的路径、版本一致性，并实际运行
Clang → opt → llvm-dis → llc → llvm-strip 编译一个最小 eBPF 程序。
`make defconfig` 后还会核对 OpenWrt 的主机 LLVM 选择和路径配置。
缺工具、版本混用或 BPF 编译失败时，会在正式编译前停止并给出具体原因，
避免等待数小时后才出现 `/invalid/clang` 错误。

Linux 本地编译也可运行（`/usr` 应替换为 LLVM 的安装前缀）：

```sh
bash scripts/check-bpf-toolchain.sh /usr /path/to/openwrt/.config
```

此检查验证主机工具链，不代替 Zen 后端交叉编译和真机 eBPF 加载验证。

### 编译耗时与增量构建

[R5C 成功构建 #36706276709](https://github.com/zdabing/10Wrt/actions/runs/36706276709)
总耗时约 2 小时 27 分钟，固件编译步骤为 2 小时 21 分 8 秒。
当前 Actions 只还原 `openwrt/dl` 下载缓存，`tools`、交叉工具链、Rust 主机编译器、
内核和软件包构建目录仍从零生成；现有官方 CI LLVM 复用已启用。
原始 OpenWrt 日志的 `time: ...#user#system#wall` 记录提供了单目标耗时：

| 构建目标 | wall 时间 |
| --- | --- |
| Rust 主机编译器 | 4774.90 秒（79 分 35 秒） |
| Python3 主机工具 | 1407.28 秒（23 分 27 秒） |
| Go bootstrap 主机工具 | 1292.81 秒（21 分 33 秒） |
| GCC initial / final | 656.75 / 616.13 秒 |
| Linux 内核编译 | 647.89 秒（10 分 48 秒） |
| Zen daemon | 138.14 秒（2 分 18 秒） |
| Zen 主题 / 应用 | 1.55 / 1.03 秒 |

这些目标部分并行执行，wall 时间不能相加当作总时长，也不能把 79.6 分钟全算作
LLVM：本次已经复用官方 CI LLVM，但仍构建两阶段 Rust 编译器、标准库和 Cargo。
Zen daemon 的记录不含其前置 Rust 主机编译器；完整冷构建仍需这些依赖。

`scripts/build-firmware.sh` 现在逐阶段记录每次尝试的并行数、耗时和退出码，保留
原有重试次数与串行兜底。结果写入 Actions Summary，并上传
`build-timings-<设备>-<运行号>` 小型 artifact（7 天）。下一次实际编译后，可明确
区分工具链、内核、软件包和失败重试的耗时；增加测量本身不宣称已缩短构建。

后续只修改 Zen 时，优先在保留的同目标 Linux OpenWrt 工作目录中单独重编三包，
保留 `staging_dir` 和工具链。替换源码后只清理修改的包，不执行整个 `dirclean`。
例如当前项目集成路径为 `package/new`：

```sh
make package/new/zen-traffic/clean
make package/new/zen-traffic/compile V=s -j"$(nproc)"
make package/new/luci-theme-zen/clean
make package/new/luci-theme-zen/compile V=s -j"$(nproc)"
make package/new/luci-app-zen-traffic/clean
make package/new/luci-app-zen-traffic/compile V=s -j"$(nproc)"
```

只改主题/应用时跳过后端两条命令。向现有路由器安装包前核对目标、固件和依赖
版本；独立出包不需要重刷整机。如采用 SDK，应匹配本次源码与 feeds，不能拿
其他目标或不同内核 ABI 的模块混装。

依据当前证据，优先复用与目标、Rust 配方、工具链和配置匹配的 Rust/host 与构建
工作目录；保存与恢复缓存后必须验证 rustc/cargo、目标标准库和构建 stamp，不能
仅触碰 stamp 跳过一个缺失的编译器。C/C++ 占比高时再考虑有大小上限、按目标
区分的 ccache，或使用持久构建机。
`ccache` 不缓存 Rust 编译，也不能单靠它保证 2.5 小时降到某个时长。GitHub
托管 runner 的完整 staging/build_dir 很大，加入缓存前需评估存储与传输成本。

R5C 构建现增加独立的 Rust 分发包缓存：首次仍按 OpenWrt 配方从源码编译并保存
完整 `build/dist/*.tar.gz`，随后由原有 `Host/Install` 安装。匹配缓存可复用这些
实际构建过的分发包；不恢复或伪造 `.built`、`.rust_installed` 等 stamp。
缓存键覆盖 OpenWrt/packages 提交、完整配置、Rust 配方/目标参数、本地工具链
修改以及主机 OS、架构、glibc/GCC 版本，没有宽泛的旧版本回退键。

命中前逐包验证 SHA256，临时安装 rustc/cargo 与主机/目标标准库，执行主机
线程程序，并用当前目标 GCC 链接目标程序核对 ELF 架构。缺失、损坏、配置
不匹配或编译器/链接验证失败，均返回原源码编译路径；源码编译失败仍使
整个构建失败。只在成功构建和固件验收后保存缓存。当前仅覆盖 R5C。

运行 `python3 scripts/test-rust-dist-cache.py` 可验证缓存损坏、身份失效、组件
缺失、拒绝未验证编译器以及 GNU make 的冷构建失败传播。实际缓存命中后的
全固件编译与冷/热耗时对照仍待验证，当前不宣称已把 2.5 小时缩短到特定时长。

---

## 致谢

- [OpenWrt](https://github.com/openwrt/openwrt)
- [xuanranran/OpenWrt_RockChip](https://github.com/xuanranran/OpenWrt_RockChip) — 参考项目
- [kenzok8/openwrt-clashoo](https://github.com/kenzok8/openwrt-clashoo) — Clashoo 双内核代理（mihomo + sing-box）
- [nikkinikki-org/OpenWrt-nikki](https://github.com/nikkinikki-org/OpenWrt-nikki) — Nikki 代理客户端
- [sbwml](https://github.com/sbwml) — 多个插件包
- [hahaher123/luci-app-oxidns](https://github.com/hahaher123/luci-app-oxidns) — OxiDNS LuCI 管理界面
- [zdabing/luci-zen](https://github.com/zdabing/luci-zen) — Zen 主题（默认）
- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)
- [SuLingGG/OpenWrt-Rpi](https://github.com/SuLingGG/OpenWrt-Rpi)

## 免责声明

本固件仅供学习研究使用，请勿用于任何商业用途。使用本固件所导致的任何损失由使用者自行承担。

### Zen 固件版本与更新信息

`openwrt` 构建前写入 `/usr/share/10wrt/release.json`，包含设备 target/profile、发布 tag、构建号及配置提交。构建后从 OpenWrt `profiles.json` 校验同设备可刷写镜像，发布 `10wrt-update.json`，并在 Release 正文附加同一元数据，供 Zen 设置页手动检查更新。R5C 使用 sysupgrade；x86 使用 combined/combined-efi，排除单独 rootfs 镜像。保留 `/etc` 配置不会覆盖这个构建标识。旧固件缺少标识时显示当前构建未知。测试：`python3 scripts/test-firmware-update-metadata.py`。
