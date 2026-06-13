#!/bin/bash
# ============================================================
# diy.sh — ImmortalWrt 自定义配置脚本
# 在 feeds 更新之后、make defconfig 之前执行
# ============================================================

set -e

echo ">>> [diy.sh] 开始自定义配置..."

# ---- 修改默认管理地址 ----
sed -i 's/192.168.1.1/10.0.0.1/g' package/base-files/files/bin/config_generate
echo ">>> 默认 LAN 地址已改为 10.0.0.1"

# ---- 创建第三方包目录 ----
mkdir -p package/new

# ---- 直接克隆单包到 package/new/（比 feed 方式更简洁）----
# 第三方仓库不稳定，单个失败不中断整个构建

clone_or_warn() {
    local repo="$1" dst="$2" name="$3"
    if git clone --depth 1 "$repo" "$dst" 2>/dev/null; then
        echo ">>> 已添加 $name"
    else
        echo "!!! 警告：$name 克隆失败，已跳过（不影响编译继续）"
    fi
}

clone_or_warn "https://github.com/sbwml/luci-app-quickfile.git"  "package/new/quickfile" "luci-app-quickfile"
clone_or_warn "https://github.com/sbwml/luci-app-mosdns.git"     "package/new/mosdns"    "luci-app-mosdns"
clone_or_warn "https://github.com/timsaya/luci-app-bandix.git"    "package/new/bandix"    "luci-app-bandix"
clone_or_warn "https://github.com/eamonxg/luci-theme-aurora.git"  "package/new/aurora"    "luci-theme-aurora"

# 将默认主题从 bootstrap 改为 aurora（aurora 克隆成功才改）
if [ -d package/new/aurora ]; then
    sed -i 's|/luci-static/bootstrap|/luci-static/aurora|g' feeds/luci/modules/luci-base/root/etc/config/luci
    echo ">>> 默认主题已改为 luci-theme-aurora"
fi

# ---- 多包 feed（kenzok8）----
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
