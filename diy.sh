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

# sbwml/luci-app-quickfile — 文件管理器
git clone --depth 1 https://github.com/sbwml/luci-app-quickfile.git package/new/quickfile
echo ">>> 已添加 luci-app-quickfile"

# sbwml/luci-app-mosdns — MosDNS
git clone --depth 1 https://github.com/sbwml/luci-app-mosdns.git package/new/mosdns
echo ">>> 已添加 luci-app-mosdns"

# timsaya/luci-app-bandix — 带宽监控
git clone --depth 1 https://github.com/timsaya/luci-app-bandix.git package/new/bandix
echo ">>> 已添加 luci-app-bandix"

# eamonxg/luci-theme-aurora — Aurora 主题
git clone --depth 1 https://github.com/eamonxg/luci-theme-aurora.git package/new/aurora
# 将默认主题从 bootstrap 改为 aurora
sed -i 's|/luci-static/bootstrap|/luci-static/aurora|g' feeds/luci/modules/luci-base/root/etc/config/luci
echo ">>> 默认主题已改为 luci-theme-aurora"

# ---- 多包 feed（kenzok8 一整个仓库很多包，仍用 feed 方式）----
echo "src-git kenzok8 https://github.com/kenzok8/openwrt-clashoo.git" >> feeds.conf.default
./scripts/feeds update kenzok8
./scripts/feeds install -a -p kenzok8
echo ">>> 已添加 kenzok8/openwrt-clashoo 软件源"

echo ">>> [diy.sh] 自定义配置完成"
