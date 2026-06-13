#!/bin/bash
# ============================================================
# diy.sh — ImmortalWrt 自定义配置脚本
# 接管 feeds 更新/安装，替换优化版软件包，添加第三方插件
# ============================================================

set -e

echo ">>> [diy.sh] 开始自定义配置..."

# ---- 编译优化：Os（体积优先）→ O2（性能优先）----
sed -i 's/Os/O2/g' include/target.mk
echo ">>> 编译优化级别：Os → O2"

# ---- 移除 SNAPSHOT 标签 ----
sed -i 's,-SNAPSHOT,,g' include/version.mk
sed -i 's,-SNAPSHOT,,g' package/base-files/image-config.in
echo ">>> 固件版本已移除 SNAPSHOT 标签"

# ---- 关闭 CPU 漏洞缓解（路由器场景用不上，换性能）----
sed -i 's,rootwait,rootwait mitigations=off,g' target/linux/rockchip/image/default.bootscript 2>/dev/null || true
sed -i 's,@CMDLINE@ noinitrd,noinitrd mitigations=off,g' target/linux/x86/image/grub-efi.cfg 2>/dev/null || true
sed -i 's,@CMDLINE@ noinitrd,noinitrd mitigations=off,g' target/linux/x86/image/grub-iso.cfg 2>/dev/null || true
sed -i 's,@CMDLINE@ noinitrd,noinitrd mitigations=off,g' target/linux/x86/image/grub-pc.cfg 2>/dev/null || true
echo ">>> CPU 漏洞缓解已关闭 (mitigations=off)"

# ---- TEO CPU 空闲调度器（比默认 menu governor 响应更快）----
KERNEL_VER=$(sed -n 's/^KERNEL_PATCHVER:=//p' target/linux/rockchip/Makefile 2>/dev/null || echo "")
[ -z "$KERNEL_VER" ] && KERNEL_VER=$(sed -n 's/^KERNEL_PATCHVER:=//p' target/linux/x86/Makefile 2>/dev/null || echo "6.12")
find target/linux/ -name "config-${KERNEL_VER}" 2>/dev/null | while read cfg; do
    if ! grep -q "CONFIG_CPU_IDLE_GOV_TEO" "$cfg" 2>/dev/null; then
        echo "CONFIG_CPU_IDLE_GOV_MENU=n" >> "$cfg"
        echo "CONFIG_CPU_IDLE_GOV_TEO=y" >> "$cfg"
    fi
done
echo ">>> CPU 空闲调度器已设为 TEO"

# ---- 修改默认管理地址 ----
sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate
echo ">>> 默认 LAN 地址已改为 10.0.0.1"

# ---- 更新 feeds ----
echo ">>> 更新 feeds..."
./scripts/feeds update -a

# ============================================================
# 替换优化版软件包（在 feeds install 之前）
# ============================================================

# ---- 1. Golang 升级到 26.x ----
echo ">>> 替换 golang 为 26.x..."
GOLANG_BACKUP=$(mktemp -d)
cp -rf feeds/packages/lang/golang "$GOLANG_BACKUP/" 2>/dev/null || true
rm -rf feeds/packages/lang/golang
if git clone --depth 1 https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang 2>/dev/null; then
    echo ">>> golang 已升级到 26.x"
else
    echo "!!! 警告：golang 26.x 拉取失败，恢复原始版本"
    cp -rf "$GOLANG_BACKUP/golang" feeds/packages/lang/ 2>/dev/null || true
fi
rm -rf "$GOLANG_BACKUP"

# ---- 2. Node.js 替换为预编译版 ----
echo ">>> 替换 Node.js 为预编译版..."
rm -rf feeds/packages/lang/node
# 从 QiuSimons/OpenWrt-Add 拉取预编译 Node（只取需要的目录）
TMP_ADD=$(mktemp -d)
git clone --depth 1 --filter=blob:none --sparse https://github.com/QiuSimons/OpenWrt-Add.git "$TMP_ADD" 2>/dev/null
cd "$TMP_ADD" && git sparse-checkout set feeds_packages_lang_node-prebuilt && cd - >/dev/null
if [ -d "$TMP_ADD/feeds_packages_lang_node-prebuilt" ]; then
    cp -rf "$TMP_ADD/feeds_packages_lang_node-prebuilt" feeds/packages/lang/node
    echo ">>> Node.js 已替换为预编译版"
else
    echo "!!! 警告：Node.js 预编译版拉取失败，使用原始版本"
fi
rm -rf "$TMP_ADD"

# ---- 安装 feeds ----
echo ">>> 安装 feeds..."
./scripts/feeds install -a

# ============================================================
# 辅助函数
# ============================================================

clone_or_warn() {
    local repo="$1" dst="$2" name="$3"
    if git clone --depth 1 "$repo" "$dst" 2>/dev/null; then
        echo ">>> 已添加 $name"
    else
        echo "!!! 警告：$name 克隆失败，已跳过"
    fi
}

# ============================================================
# 第三方插件 - 从 QiuSimons/OpenWrt-Add 批量获取
# ============================================================

mkdir -p package/new

echo ">>> 克隆 QiuSimons/OpenWrt-Add 软件包合集..."
OPENWRT_ADD_DIR="package/new"
if git clone --depth 1 https://github.com/QiuSimons/OpenWrt-Add.git "$OPENWRT_ADD_DIR/openwrt-add" 2>/dev/null; then
    # 将合集目录下所有包软链接到 package/new/ 下（跳过非包目录）
    pushd "$OPENWRT_ADD_DIR" >/dev/null
    for pkg in openwrt-add/*/; do
        pkgname=$(basename "$pkg")
        # 跳过非包目录（dotfiles、脚本、仓库根目录）
        [ -f "${pkg}Makefile" ] || [ -f "${pkg}README.md" ] || continue
        rm -rf "$pkgname" 2>/dev/null || true
        mv "$pkg" "$pkgname"
    done
    rm -rf openwrt-add
    popd >/dev/null
    echo ">>> QiuSimons/OpenWrt-Add 已展开到 package/new/"
else
    echo "!!! 警告：OpenWrt-Add 克隆失败，回退逐个克隆..."
    # 回退：逐个克隆必须的包
    clone_or_warn "https://github.com/timsaya/openwrt-bandix.git"   "package/new/bandix"    "bandix 后端"
    clone_or_warn "https://github.com/sbwml/luci-app-quickfile.git" "package/new/quickfile" "luci-app-quickfile"
    clone_or_warn "https://github.com/sbwml/luci-app-mosdns.git"    "package/new/mosdns"    "luci-app-mosdns"
    clone_or_warn "https://github.com/timsaya/luci-app-bandix.git"  "package/new/bandix-luci" "luci-app-bandix"
fi

# ---- 额外包（不在 QiuSimons 合集里的）----
clone_or_warn "https://github.com/eamonxg/luci-theme-aurora.git"  "package/new/aurora"    "luci-theme-aurora"

# 将默认主题从 bootstrap 改为 aurora
if [ -d package/new/aurora ]; then
    sed -i 's|/luci-static/bootstrap|/luci-static/aurora|g' feeds/luci/modules/luci-base/root/etc/config/luci
    echo ">>> 默认主题已改为 luci-theme-aurora"
fi

# ---- kenzok8 feed ----
KENZOK8_FEED="src-git kenzok8 https://github.com/kenzok8/openwrt-clashoo.git"
if ! grep -qF "$KENZOK8_FEED" feeds.conf.default; then
    echo "$KENZOK8_FEED" >> feeds.conf.default
    ./scripts/feeds update kenzok8
    ./scripts/feeds install -a -p kenzok8
    echo ">>> 已添加 kenzok8/openwrt-clashoo 软件源"
else
    echo ">>> kenzok8 feed 已存在，跳过"
fi

echo ">>> [diy.sh] 自定义配置完成"
