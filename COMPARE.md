# 三项目对比分析

| | **10Wrt** (我们的) | **YAOF** (zdabing fork) | **RockChip** (xuanranran) |
|---|---|---|---|
| **Runner** | GitHub `ubuntu-latest` | self-hosted | self-hosted |
| **设备** | R5C / x86_64 | R5C / x86 | 24个 Rockchip 设备 |
| **内核** | 默认 | BBRv3+LRNG+SFE+Fullcone | LRNG+natflow+DPDK+BTF/BPF |
| **GCC** | 16 | 默认 | **16** |
| **binutils** | 2.46 | 默认 | **2.46** |
| **包管理** | APK | opkg | **APK** (Alpine) |
| **编译** | 分7步+重试 | 未知 | 分阶段+重试 |
| **发布** | Artifact + Release | Release | Release |

---

## xuanranran/RockChip 独有亮点

### 1. APK 替代 opkg
```
CONFIG_USE_APK=y
CONFIG_PACKAGE_apk-openssl=y
CONFIG_PACKAGE_opkg=n
```
- **优势**：包安装速度快数倍，依赖解析更可靠
- **代价**：ImmortalWrt 25.12 已内置支持，零代价

### 2. GCC 16 + binutils 2.46
- GCC 16 对 ARMv8 的优化更好
- 需确认 ImmortalWrt 25.12 的工具链是否支持 GCC 16

### 3. BPF/BPF Toolchain
```
CONFIG_BPF_TOOLCHAIN_HOST=y
CONFIG_KERNEL_DEBUG_INFO_BTF=y
CONFIG_PACKAGE_kmod-sched-bpf=y
```
- DAE/DAED 等代理需要 BTF
- 你种子里的 `luci-app-nikki` 可能也需要

### 4. natflow + DPDK
```
CONFIG_PACKAGE_natflow=m
CONFIG_PACKAGE_dpdk-tools=y
```
- **natflow**：硬件加速流卸载，比 SFE 更激进
- **DPDK**：用户态高速包处理

### 5. Rockchip NPU 支持
```
CONFIG_PACKAGE_kmod-rocket-rockchip=y
```
- RK3568 的 NPU 驱动，AI 推理加速

### 6. Video 硬解
```
CONFIG_PACKAGE_kmod-drm-rockchip=y
CONFIG_PACKAGE_kmod-rkvdec=y
```

---

## YAOF 独有亮点

### SFE (Shortcut-FE) + Fast Classifier
```
CONFIG_PACKAGE_kmod-shortcut-fe-cm=y
CONFIG_PACKAGE_kmod-fast-classifier=y
```
- 两个配合使用，路由转发性能翻倍

### BBRv3 + LRNG (内核 Patch)
- 需复制 PATCH 目录，维护成本中等

### DAE 代理
```
CONFIG_PACKAGE_luci-app-dae=y
CONFIG_PACKAGE_dae=y
CONFIG_PACKAGE_vmlinux-btf=y
```
- 需要 BTF，编译时间显著增加

---

## 已搬入 10Wrt ✅

| 改动 | 状态 |
|---|---|
| `CONFIG_USE_APK=y` — APK 包管理 | ✅ 已启用 |
| `CONFIG_ZLIB_OPTIMIZE_SPEED=y` — zlib 速度优化 | ✅ 已启用 |
| `CONFIG_OPENSSL_OPTIMIZE_SPEED=y` — OpenSSL 速度优化 | ✅ 已启用 |
| `CONFIG_PACKAGE_kmod-fast-classifier=y` — 快速分类器 | ✅ 已启用 |
| `CONFIG_PACKAGE_nat6=y` — IPv6 NAT | ✅ 已启用 |
| GCC 16 + binutils 2.46 | ✅ 已启用 |
| BTF/BPF 支持（`CONFIG_KERNEL_DEBUG_INFO_BTF=y` 等） | ✅ 已启用 |
| `luci-app-daed` — daed 代理客户端（eBPF） | ✅ 已启用 |

## 尚未搬入（按性价比排序）

| 优先级 | 改动 | 来源 |
|---|---|---|
| ⭐⭐⭐ | `CONFIG_KERNEL_CPUSETS=y` — CPU 亲和性 | RockChip |
| ⭐⭐ | `CONFIG_ALL_KMODS=y` — 编译所有内核模块 | YAOF |

### 需额外工作

| 改动 | 工作量 |
|---|---|
| SFE + Fast Classifier kmod | 需 patch 内核（从 YAOF 搬） |
| natflow | 需 patch |
| Rockchip NPU / Video | 需 kernel config 调整 |

---

## 当前 10Wrt vs 两个参考项目的最大差距

1. **没有 SFE/快速转发** — 路由性能差一截（已有 fast-classifier，但缺 shortcut-fe 内核 patch）
2. **没有 LRNG** — 随机数性能不如 YAOF
3. **没有 natflow** — 硬件加速流卸载缺失
