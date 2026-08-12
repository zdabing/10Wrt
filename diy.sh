#!/bin/bash
# ============================================================
# diy.sh — ImmortalWrt 自定义配置脚本
# 接管 feeds 更新/安装，替换优化版软件包，添加第三方插件
# ============================================================

set -e

echo ">>> [diy.sh] 开始自定义配置..."

# ---- 编译优化：Os（体积优先）→ O2（性能优先）----
sed -i 's/-Os/-O2/g' include/target.mk
echo ">>> 编译优化级别：Os → O2"

# ---- 在版本信息中附加 immortalwrt 源码提交日期 ----
# 取当前 immortalwrt 仓库 HEAD 提交的日期（即这份代码基于的上游提交日）
# 直接写入 base-files 的 openwrt_release / banner，不依赖 version.mk 模板，跨版本（含 26.x）通用
BUILD_DATE=$(git show -s --format=%cs HEAD 2>/dev/null || date +%Y-%m-%d)
RELEASE_FILE="package/base-files/files/etc/openwrt_release"
if [ -f "$RELEASE_FILE" ]; then
    if grep -q "^BUILD_DATE=" "$RELEASE_FILE"; then
        sed -i "s/^BUILD_DATE=.*/BUILD_DATE='${BUILD_DATE}'/" "$RELEASE_FILE"
    else
        echo "BUILD_DATE='${BUILD_DATE}'" >> "$RELEASE_FILE"
    fi
    echo ">>> 构建日期已写入 openwrt_release: ${BUILD_DATE}"
fi
# 写入 SSH 登录 banner
BANNER_FILE="package/base-files/files/etc/banner"
if [ -f "$BANNER_FILE" ]; then
    sed -i "/Build date:/d" "$BANNER_FILE"
    # 同时把编译信息追加到 banner 描述行（LuCI 概览页显示的就是这一行）
    sed -i "s/ImmortalWrt [^ ]* [^,]*, [^ ]*/& (Build ${BUILD_DATE})/" "$BANNER_FILE"
    echo "Build date: ${BUILD_DATE}" >> "$BANNER_FILE"
    echo ">>> 构建日期已写入 banner"
fi

# ---- 关闭 CPU 漏洞缓解（路由器场景用不上，换性能）----
sed -i 's,rootwait,rootwait mitigations=off pci=realloc,g' target/linux/rockchip/image/default.bootscript 2>/dev/null || true
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
NODE_BACKUP=$(mktemp -d)
cp -rf feeds/packages/lang/node "$NODE_BACKUP/" 2>/dev/null || true
rm -rf feeds/packages/lang/node
TMP_ADD=$(mktemp -d)
git clone --depth 1 --filter=blob:none --sparse https://github.com/QiuSimons/OpenWrt-Add.git "$TMP_ADD" 2>/dev/null
(cd "$TMP_ADD" && git sparse-checkout set feeds_packages_lang_node-prebuilt)
if [ -d "$TMP_ADD/feeds_packages_lang_node-prebuilt" ]; then
    cp -rf "$TMP_ADD/feeds_packages_lang_node-prebuilt" feeds/packages/lang/node
    echo ">>> Node.js 已替换为预编译版"
else
    echo "!!! 警告：Node.js 预编译版拉取失败，恢复原始版本"
    cp -rf "$NODE_BACKUP/node" feeds/packages/lang/ 2>/dev/null || true
fi
rm -rf "$TMP_ADD" "$NODE_BACKUP"

# ---- Nginx / uwsgi 性能优化（参考 YAOF） ----
echo ">>> Nginx / uwsgi 性能优化..."
# Nginx
sed -i "s/large_client_header_buffers 2 1k/large_client_header_buffers 4 32k/g" feeds/packages/net/nginx-util/files/uci.conf.template 2>/dev/null || true
sed -i "s/client_max_body_size 128M/client_max_body_size 2048M/g" feeds/packages/net/nginx-util/files/uci.conf.template 2>/dev/null || true
sed -i '/client_max_body_size/a\\tclient_body_buffer_size 8192M;' feeds/packages/net/nginx-util/files/uci.conf.template 2>/dev/null || true
sed -i '/client_max_body_size/a\\tserver_names_hash_bucket_size 128;' feeds/packages/net/nginx-util/files/uci.conf.template 2>/dev/null || true
sed -i '/ubus_parallel_req/a\        ubus_script_timeout 600;' feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support 2>/dev/null || true
sed -ri "/luci-webui.socket/i\ \t\tuwsgi_send_timeout 600\;\n\t\tuwsgi_connect_timeout 600\;\n\t\tuwsgi_read_timeout 600\;" feeds/packages/net/nginx/files-luci-support/luci.locations 2>/dev/null || true
sed -ri "/luci-cgi_io.socket/i\ \t\tuwsgi_send_timeout 600\;\n\t\tuwsgi_connect_timeout 600\;\n\t\tuwsgi_read_timeout 600\;" feeds/packages/net/nginx/files-luci-support/luci.locations 2>/dev/null || true
# uwsgi
sed -i 's,procd_set_param stderr 1,procd_set_param stderr 0,g' feeds/packages/net/uwsgi/files/uwsgi.init 2>/dev/null || true
sed -i 's,buffer-size = 10000,buffer-size = 131072,g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini 2>/dev/null || true
sed -i 's,logger = luci,#logger = luci,g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini 2>/dev/null || true
sed -i '$a cgi-timeout = 600' feeds/packages/net/uwsgi/files-luci-support/luci-*.ini 2>/dev/null || true
sed -i 's/threads = 1/threads = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini 2>/dev/null || true
sed -i 's/processes = 3/processes = 4/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini 2>/dev/null || true
sed -i 's/cheaper = 1/cheaper = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini 2>/dev/null || true
# rpcd
sed -i 's/option timeout 30/option timeout 60/g' package/system/rpcd/files/rpcd.config 2>/dev/null || true
sed -i 's#20) \* 1000#60) \* 1000#g' feeds/luci/modules/luci-base/htdocs/luci-static/resources/rpc.js 2>/dev/null || true

# ---- 移除官方 v2ray-geodata（与 mosdns 版本冲突）----
rm -rf feeds/packages/net/v2ray-geodata 2>/dev/null || true

# ---- 安装 feeds ----
echo ">>> 安装 feeds..."
./scripts/feeds install -a

# ============================================================
# 第三方插件（feeds install -a 之后添加，再注册进 feeds）
# ============================================================

mkdir -p package/new

clone_or_warn() {
    local repo="$1" dst="$2" name="$3" branch="$4"
    local branch_opt=""
    [ -n "$branch" ] && branch_opt="-b $branch"
    if git clone --depth 1 $branch_opt "$repo" "$dst" 2>/dev/null; then
        echo ">>> 已添加 $name"
    else
        echo "!!! 警告：$name 克隆失败，已跳过"
    fi
}

clone_or_warn "https://github.com/timsaya/openwrt-bandix.git"     "package/new/bandix-tmp" "bandix 后端"
# openwrt-bandix 仓库嵌套了 openwrt-bandix/ 子目录，需要展开
if [ -d "package/new/bandix-tmp/openwrt-bandix" ]; then
    mkdir -p package/new/bandix
    cp -rf package/new/bandix-tmp/openwrt-bandix/. package/new/bandix/
    rm -rf package/new/bandix-tmp
    echo ">>> bandix 后端目录已展开"
elif [ -d "package/new/bandix-tmp" ]; then
    mv package/new/bandix-tmp package/new/bandix
fi
clone_or_warn "https://github.com/timsaya/luci-app-bandix.git"    "package/new/bandix-luci" "luci-app-bandix（前端）"
clone_or_warn "https://github.com/sbwml/luci-app-quickfile.git"   "package/new/quickfile" "luci-app-quickfile"
clone_or_warn "https://github.com/svenshi/luci-app-oxidns.git"    "package/new/luci-app-oxidns" "luci-app-oxidns"
clone_or_warn "https://github.com/eamonxg/luci-theme-aurora.git"  "package/new/luci-theme-aurora"    "luci-theme-aurora"
# ---- 克隆 MiClash（luci-app-miclash 在子目录中）----
clone_or_warn "https://github.com/ang3el7z/luci-app-miclash.git" "package/new/miclash-tmp" "luci-app-miclash"
if [ -d "package/new/miclash-tmp/luci-app-miclash" ]; then
    mv package/new/miclash-tmp/luci-app-miclash package/new/luci-app-miclash
    rm -rf package/new/miclash-tmp
    echo ">>> luci-app-miclash 已展开到 package/new/luci-app-miclash"
fi
# ---- fwx 内核模块+守护进程（fanchmwrt，实时流量/应用识别 Dashboard）----
# fanchmwrt 主仓库是完整 OpenWrt 源码树，只取 package/fcm（kmod-fwx / fwxd / libfwx_common）。
# 固定 fanchmwrt-25.12.4 分支（kernel 6.12，与 ImmortalWrt 25.12 一致）。
# LuCI 前端在独立 feed（fanchmwrt/fanchmwrt-packages），见下方 feeds 区。
clone_or_warn "https://github.com/fanchmwrt/fanchmwrt.git" "package/new/fcm-tmp" "fwx 后端（kmod-fwx/fwxd）" "fanchmwrt-25.12.4"
if [ -d "package/new/fcm-tmp/package/fcm" ]; then
    mkdir -p package/new/fcm
    cp -rf package/new/fcm-tmp/package/fcm/. package/new/fcm/
    rm -rf package/new/fcm-tmp
    echo ">>> fcm（fwx 内核模块+守护进程）已展开到 package/new/fcm"
else
    echo "!!! 警告：fcm 目录展开失败，已保留原始克隆"
fi
# clone_or_warn "https://github.com/nikkinikki-org/OpenWrt-nikki.git" "package/new/nikki"    "luci-app-nikki"  # 已注释：不再使用

# ---- Mihomo 格式 geodata（来自 MetaCubeX/meta-rules-dat）----
# 关键：Clashoo 基于 Mihomo 内核，需要 MetaCubeX 格式的 geodata！
# 不能用 V2Ray 格式（/usr/share/v2ray/geosite.dat）混用，否则报：
#   "list cn not found" / "proto: cannot parse invalid wire-format data"
#
# 各组件 geodata 分布：
#   /usr/share/v2ray/geosite.dat  → V2Ray 格式（sbwml/v2ray-geodata）→ V2Ray/MosDNS
#   /etc/nikki/run/GeoSite.dat    → Mihomo 格式（MetaCubeX）         → Nikki  # 已注释
#   /etc/clashoo/GeoSite.dat      → Mihomo 格式（MetaCubeX）         → Clashoo
#   /usr/share/daed/geosite.dat   → daed 自带                        → Daed  # 已注释
#   HomeProxy(sing-box)           → .srs rule_set 远程下载           → 不用本地 geodata
echo ">>> 下载 Mihomo 格式 geodata (MetaCubeX/meta-rules-dat)..."
META_GEO_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/latest/download"

# Nikki 工作目录: /etc/nikki/run/
# mkdir -p files/etc/nikki/run
# wget -q --show-progress -O files/etc/nikki/run/GeoSite.dat "${META_GEO_URL}/geosite.dat" || echo "!!! 警告：Nikki GeoSite.dat 下载失败"
# wget -q --show-progress -O files/etc/nikki/run/GeoIP.dat   "${META_GEO_URL}/geoip.dat"   || echo "!!! 警告：Nikki GeoIP.dat 下载失败"
# echo ">>> Nikki geodata → files/etc/nikki/run/"

# Clashoo 工作目录: /etc/clashoo/
# mkdir -p files/etc/clashoo
# wget -q --show-progress -O files/etc/clashoo/GeoSite.dat   "${META_GEO_URL}/geosite.dat" || echo "!!! 警告：Clashoo GeoSite.dat 下载失败"
# wget -q --show-progress -O files/etc/clashoo/GeoIP.dat     "${META_GEO_URL}/geoip.dat"   || echo "!!! 警告：Clashoo GeoIP.dat 下载失败"
# echo ">>> Clashoo geodata → files/etc/clashoo/"

# ---- MosDNS v5 ----
echo ">>> 添加 MosDNS v5..."
find ./ | grep Makefile | grep v2ray-geodata | xargs rm -f 2>/dev/null || true
find ./ | grep Makefile | grep mosdns | xargs rm -f 2>/dev/null || true
clone_or_warn "https://github.com/sbwml/luci-app-mosdns.git" "package/new/mosdns" "MosDNS v5" "v5"
clone_or_warn "https://github.com/sbwml/v2ray-geodata.git"         "package/new/v2ray-geodata" "v2ray-geodata"

# 将默认主题从 bootstrap 改为 aurora
if [ -d package/new/luci-theme-aurora ]; then
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

# ---- fanchmwrt feed（fwx LuCI 前端：dashboard/appfilter/session-stat 等）----
# 后端（kmod-fwx/fwxd）由上方 package/new/fcm 提供；本 feed 提供 14 个 luci-app-fwx-*。
# 特征库 feature.cfg 版权归 destan19/fanchmwrt（个人免费、禁商用）。
FANCHMWRT_FEED="src-git fanchmwrt https://github.com/fanchmwrt/fanchmwrt-packages.git"
if ! grep -qF "$FANCHMWRT_FEED" feeds.conf.default; then
    echo "$FANCHMWRT_FEED" >> feeds.conf.default
    ./scripts/feeds update fanchmwrt
    ./scripts/feeds install -a -p fanchmwrt
    echo ">>> 已添加 fanchmwrt/fanchmwrt-packages 软件源"
else
    echo ">>> fanchmwrt feed 已存在，跳过"
fi

# ---- 将 package/new 注册为本地 feed ----
echo ">>> 注册 package/new 为本地 feed..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NEW_FEED="src-link new ${SCRIPT_DIR}/package/new"
if ! grep -qF "$NEW_FEED" feeds.conf.default; then
    echo "$NEW_FEED" >> feeds.conf.default
fi
./scripts/feeds update new
./scripts/feeds install -a -p new
echo ">>> package/new 已注册并安装到 feeds"

echo ">>> [diy.sh] 自定义配置完成"
