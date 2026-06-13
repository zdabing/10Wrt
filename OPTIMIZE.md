# 10Wrt 优化方案（参考 YAOF）

> 来源：https://github.com/zdabing/YAOF (fork 自 QiuSimons/YAOF)  
> 分支：`25.12` | 适用目标：NanoPi R5C / x86_64

---

## 1. 编译优化

### 1.1 O2 编译（当前 Os）

```bash
sed -i 's/Os/O2/g' include/target.mk
```

- **效果**：Os 压缩代码体积，O2 平衡性能与体积
- **代价**：固件约增大 5-10%

### 1.2 关闭 CPU 漏洞缓解

```bash
# Rockchip
sed -i 's,rootwait,rootwait mitigations=off,g' target/linux/rockchip/image/default.bootscript
# x86
sed -i 's,@CMDLINE@ noinitrd,noinitrd mitigations=off,g' target/linux/x86/image/grub-efi.cfg
```

- **效果**：内核不加载 Spectre/Meltdown 等漏洞缓解，CPU 性能显著提升
- **代价**：理论上降低安全性（家用路由器场景可忽略）

### 1.3 TEO CPU 空闲调度器

```bash
cat >> target/linux/generic/config-6.12 << 'EOF'
CONFIG_CPU_IDLE_GOV_MENU=n
CONFIG_CPU_IDLE_GOV_TEO=y
EOF
```

- **效果**：TEO (Timer Events Oriented) 比默认 menu governor 更快响应、更低延迟

---

## 2. 内核强化

### 2.1 BBRv3 拥塞控制

- **源**：`YAOF/PATCH/kernel/bbr3/` → `target/linux/generic/backport-6.12/`
- **效果**：Google BBRv3，比内核自带的 BBRv1 更公平、收敛更快
- **依赖**：需要 `CONFIG_TCP_CONG_BBR=y`（10Wrt 已有）

### 2.2 LRNG 随机数生成器

- **源**：`YAOF/PATCH/kernel/lrng/` → `target/linux/generic/hack-6.12/`
- **效果**：替代内核 `/dev/urandom`，速度更快、熵质量更高
- **额外配置**：
```
CONFIG_LRNG=y
CONFIG_LRNG_DEV_IF=y
CONFIG_LRNG_JENT=y
CONFIG_LRNG_CPU=y
CONFIG_LRNG_SELFTEST=y
```

### 2.3 Fullcone NAT 全套

当前 10Wrt 只有 `CONFIG_PACKAGE_kmod-nft-fullcone=y`，YAOF 额外补了：

| 组件 | 说明 |
|---|---|
| `YAOF/PATCH/kernel/bcmfullcone/` | 内核层 Broadcom Fullcone |
| `YAOF/PATCH/pkgs/firewall/libnftnl/*.patch` | libnftnl 支持 |
| `YAOF/PATCH/pkgs/firewall/nftables/*.patch` | nftables 支持 |
| `YAOF/PATCH/pkgs/firewall/luci/0001-*.patch` | LuCI 界面 FullCone 开关 |
| `YAOF/PATCH/pkgs/firewall/luci/0007-*.patch` | Fullcone6 (IPv6) |

### 2.4 Shortcut-FE / NAT6 / natflow

| 功能 | 补丁 |
|---|---|
| Shortcut-FE (硬件加速) | `YAOF/PATCH/kernel/sfe/` + LuCI patch 0002 |
| NAT6 (IPv6 NAT) | firewall4 patch + LuCI patch 0003 |
| 自定义 nft 规则 | LuCI patch 0004 |
| natflow 负载分流 | LuCI patch 0005 |

### 2.5 NETKIT

```bash
cat >> target/linux/generic/config-6.12 << 'EOF'
CONFIG_NETKIT=y
CONFIG_IPV6_MULTIPLE_TABLES=y
EOF
```

---

## 3. 软件包替换与强化

### 3.1 Node.js 预编译版

```bash
rm -rf feeds/packages/lang/node
cp -rf ../OpenWrt-Add/feeds_packages_lang_node-prebuilt feeds/packages/lang/node
```

- **原因**：Node.js 交叉编译极慢且容易失败，预编译版直接可用

### 3.2 Golang 升级

```bash
rm -rf feeds/packages/lang/golang
cp -rf ../openwrt_pkg_ma/lang/golang feeds/packages/lang/golang
# 或直接拉 sbwml 的 26.x 版本
# git clone https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang
```

### 3.3 移除 SNAPSHOT 标签

```bash
sed -i 's,-SNAPSHOT,,g' include/version.mk
sed -i 's,-SNAPSHOT,,g' package/base-files/image-config.in
```

- **效果**：固件版本从 `ImmortalWrt 25.12-SNAPSHOT` → `ImmortalWrt 25.12`

### 3.4 内核版本校验

```bash
SUPPORTED_KERNEL="6.12"
current_version=$(sed -n 's/^KERNEL_PATCHVER:=//p' ./target/linux/rockchip/Makefile)
if [ "$SUPPORTED_KERNEL" != "$current_version" ]; then
    echo "错误：编译内核版本 $current_version，预期 $SUPPORTED_KERNEL"
    exit 1
fi
```

- **效果**：大版本升级内核变更时立即报错，而不是静默出问题

---

## 4. Nginx + uWSGI 调优

```bash
# 大文件上传
sed -i "s/client_max_body_size 128M/client_max_body_size 2048M/g" feeds/packages/net/nginx-util/files/uci.conf.template
sed -i '/client_max_body_size/a\\tclient_body_buffer_size 8192M;' feeds/packages/net/nginx-util/files/uci.conf.template

# Header 缓冲区
sed -i "s/large_client_header_buffers 2 1k/large_client_header_buffers 4 32k/g" feeds/packages/net/nginx-util/files/uci.conf.template
sed -i '/client_max_body_size/a\\tserver_names_hash_bucket_size 128;' feeds/packages/net/nginx-util/files/uci.conf.template

# uwsgi 超时
sed -ri "/luci-webui.socket/i\ \t\tuwsgi_send_timeout 600\;\n\t\tuwsgi_connect_timeout 600\;\n\t\tuwsgi_read_timeout 600\;" feeds/packages/net/nginx/files-luci-support/luci.locations

# uwsgi 进程数
sed -i 's/threads = 1/threads = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's/processes = 3/processes = 4/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini

# rpcd 超时
sed -i 's/option timeout 30/option timeout 60/g' package/system/rpcd/files/rpcd.config
sed -i 's#20) \* 1000#60) \* 1000#g' feeds/luci/modules/luci-base/htdocs/luci-static/resources/rpc.js
```

---

## 5. 其他

### 5.1 fuck 命令

```bash
mkdir -p package/base-files/files/usr/bin
cp -f ../OpenWrt-Add/fuck package/base-files/files/usr/bin/fuck
```

- **效果**：SSH 输入 `fuck` 自动修复常见问题并重启

### 5.2 i225/i226 网卡 EEE 禁用

```bash
cp -rf ../PATCH/kernel/igc/* target/linux/x86/patches-6.12/
```

- **效果**：修复 Intel I225/I226 断流问题

### 5.3 定时编译

```yaml
on:
  schedule:
    - cron: 0 4 * * 5   # 每周五凌晨4点
```

---

## 迁移步骤建议

### 第一阶段：低风险（直接改脚本）
1. O2 编译 → 一行 sed
2. mitigations=off → 几行 sed
3. 移除 SNAPSHOT → 两行 sed
4. 内核版本校验 → 10 行 bash
5. Nginx/uwsgi 调优 → 纯 sed

### 第二阶段：需要 PATCH 目录
6. 复制 `YAOF/PATCH/` 到 10Wrt
7. BBRv3 + LRNG + 全锥NAT 全套
8. Shortcut-FE / NAT6 / natflow
9. Node.js 预编译版
10. fuck 命令

### 第三阶段：工作流优化
11. Matrix 复用（合并 R5C/X86 共同逻辑）
12. 定时编译
