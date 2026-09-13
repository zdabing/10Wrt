#!/bin/bash
# ============================================================
# diy.sh — OpenWrt 自定义配置脚本
# 接管 feeds 更新/安装，替换优化版软件包，添加第三方插件
# ============================================================

set -e

echo ">>> [diy.sh] 开始自定义配置..."

# ---- 编译优化：Os（体积优先）→ O2（性能优先）----
sed -i 's/-Os/-O2/g' include/target.mk
echo ">>> 编译优化级别：Os → O2"

# ---- 在版本信息中附加 openwrt 源码提交日期 ----
# 取当前 openwrt 仓库 HEAD 提交的日期（即这份代码基于的上游提交日）
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
    sed -i "s/OpenWrt [^ ]* [^,]*, [^ ]*/& (Build ${BUILD_DATE})/" "$BANNER_FILE"
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

# ---- Node.js 替换为预编译版 ----
echo ">>> 替换 Node.js 为预编译版..."
NODE_BACKUP=$(mktemp -d)
cp -rf feeds/packages/lang/node "$NODE_BACKUP/" 2>/dev/null || true
rm -rf feeds/packages/lang/node
TMP_ADD=$(mktemp -d)
if git clone --depth 1 --filter=blob:none --sparse https://github.com/QiuSimons/OpenWrt-Add.git "$TMP_ADD" 2>/dev/null && \
   (cd "$TMP_ADD" && git sparse-checkout set feeds_packages_lang_node-prebuilt) && \
   [ -d "$TMP_ADD/feeds_packages_lang_node-prebuilt" ]; then
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
# 大请求超过缓冲区后写入临时文件，避免在内存有限的路由器上为上传分配数 GiB 内存。
sed -i '/client_body_buffer_size/d' feeds/packages/net/nginx-util/files/uci.conf.template 2>/dev/null || true
sed -i '/client_max_body_size/a\\tclient_body_buffer_size 512K;' feeds/packages/net/nginx-util/files/uci.conf.template 2>/dev/null || true
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

# ---- 安装 feeds ----
echo ">>> 安装 feeds..."
./scripts/feeds install -a

# ============================================================
# 第三方插件（feeds install -a 之后添加，再注册进 feeds）
# ============================================================

mkdir -p package/new

clone_required() {
    local repo="$1" dst="$2" name="$3" branch="$4"
    local branch_opt=""
    [ -n "$branch" ] && branch_opt="-b $branch"
    if git clone --depth 1 $branch_opt "$repo" "$dst" 2>/dev/null; then
        echo ">>> 已添加 $name"
    else
        rm -rf "$dst"
        echo "!!! 错误：必需软件源 $name 克隆失败"
        return 1
    fi
}

clone_required "https://github.com/timsaya/openwrt-bandix.git"     "package/new/bandix-tmp" "bandix 后端"
# openwrt-bandix 仓库嵌套了 openwrt-bandix/ 子目录，需要展开
if [ -d "package/new/bandix-tmp/openwrt-bandix" ]; then
    mkdir -p package/new/bandix
    cp -rf package/new/bandix-tmp/openwrt-bandix/. package/new/bandix/
    rm -rf package/new/bandix-tmp
    echo ">>> bandix 后端目录已展开"
elif [ -d "package/new/bandix-tmp" ]; then
    mv package/new/bandix-tmp package/new/bandix
fi
clone_required "https://github.com/timsaya/luci-app-bandix.git" "package/new/bandix-luci" "luci-app-bandix（前端）"
clone_required "https://github.com/sbwml/luci-app-quickfile.git" "package/new/quickfile" "luci-app-quickfile"
clone_required "https://github.com/svenshi/luci-app-oxidns.git" "package/new/luci-app-oxidns" "luci-app-oxidns"
clone_required "https://github.com/LianXia233/luci-theme-mint.git" "package/new/mint-tmp" "luci-theme-mint"
# mint 仓库根目录是 theme/（主题）与 wallpaper/（壁纸设置）两个包目录。
# 只展开 theme/：luci-app-mint-wallpaper（壁纸设置页/rpcd 后端/随机壁纸 cron）不安装。
# 主题模板渲染所需的 ucode 模块 luci.mint.wallpaper（只读）在主题包内，
# 去掉 app 后主题照常工作，仅失去自定义壁纸入口（内置角色背景不受影响）。
if [ -d "package/new/mint-tmp/theme" ]; then
    # 上游 Makefile 把 PKG_VERSION/PKG_PO_VERSION 置空、由其 CI 注入版本号；
    # 空值会短路 luci.mk 的 findrev 推导，导致翻译包 VERSION 为空而编译失败。
    # 这里取 mint 仓库 HEAD 的提交日期+短哈希生成版本号（findrev 同款格式），
    # 展开时写入 Makefile，等价于上游 CI 的注入动作。
    MINT_HASH=$(git -C package/new/mint-tmp rev-parse --short=7 HEAD 2>/dev/null || echo "0000000")
    MINT_SECS=$(git -C package/new/mint-tmp log -1 --format=%ct 2>/dev/null || echo "0")
    MINT_VER="$(date -u -d "@${MINT_SECS}" '+%y.%j')~${MINT_HASH}"
    mkdir -p package/new/luci-theme-mint
    cp -rf package/new/mint-tmp/theme/. package/new/luci-theme-mint/
    rm -rf package/new/mint-tmp
    echo ">>> mint 主题已展开（版本 ${MINT_VER}，壁纸设置包不安装）"
else
    echo "!!! 错误：mint 仓库结构已变（未找到 theme/ 子目录）"
    exit 1
fi
# Mint 的 Makefile 用相对路径 include ../../luci.mk，只有放在 LuCI feed 内才解析得到。
# 本项目把第三方包放在 package/new（注册为 src-link feed），必须改成绝对路径，
# 否则 include 找不到 luci.mk，编译在开始前就失败。
for MINT_MK in package/new/luci-theme-mint/Makefile; do
    if [ -f "$MINT_MK" ]; then
        sed -i 's|include \.\./\.\./luci\.mk|include $(TOPDIR)/feeds/luci/luci.mk|' "$MINT_MK"
        grep -qF 'include $(TOPDIR)/feeds/luci/luci.mk' "$MINT_MK" || {
            echo "!!! 错误：$MINT_MK 的 luci.mk 引用修正失败（上游 Makefile 结构可能已变）"
            exit 1
        }
        # 注入版本号（上游留空交给其 CI 注入，见上方说明）
        sed -i "s|^PKG_VERSION *?=\$|PKG_VERSION := ${MINT_VER}|; s|^PKG_PO_VERSION *?=\$|PKG_PO_VERSION := ${MINT_VER}|" "$MINT_MK"
        grep -qF "PKG_VERSION := ${MINT_VER}" "$MINT_MK" && grep -qF "PKG_PO_VERSION := ${MINT_VER}" "$MINT_MK" || {
            echo "!!! 错误：$MINT_MK 的版本号注入失败（上游 Makefile 结构可能已变）"
            exit 1
        }
    fi
done
echo ">>> Mint 主题 Makefile 的 luci.mk 引用已修正为绝对路径，版本号已注入"
# ---- Mint 模板 ucode 兼容补丁（openwrt-25.12 分支必需）----
# 25.12 分支的 ucode（2026.01.16）不支持命名导出语法 export function name(){}：
# 模块能编译但导出表为空，header.ut 的 import { getWallpapers } 报
# "Module ... does not export 'getWallpapers'"，模板编译失败后 LuCI 静默
# 回退 bootstrap，表现为"固件里有 mint 但主题不生效"。
# 改成 export default + 默认导入写法（新旧 ucode 均支持，上游 main 同样可用）。
# 上游若新增导出或改用其它语法，下方校验会失败退出。
MINT_UC="package/new/luci-theme-mint/ucode/mint/wallpaper.uc"
MINT_UT="package/new/luci-theme-mint/ucode/template/themes/mint/header.ut"
sed -i 's|^export function getWallpapers() {|function getWallpapers() {|' "$MINT_UC"
printf '\nexport default { getWallpapers: getWallpapers };\n' >> "$MINT_UC"
sed -i 's|import { getWallpapers } from .luci.mint.wallpaper.;|import mintwp from "luci.mint.wallpaper";|' "$MINT_UT"
sed -i 's|wallpaper = getWallpapers();|wallpaper = mintwp.getWallpapers();|' "$MINT_UT"
grep -q '^function getWallpapers()' "$MINT_UC" && \
  grep -q '^export default { getWallpapers: getWallpapers };' "$MINT_UC" && \
  grep -qF 'import mintwp from "luci.mint.wallpaper"' "$MINT_UT" && \
  grep -qF 'mintwp.getWallpapers()' "$MINT_UT" || {
    echo "!!! 错误：Mint 模板 ucode 兼容补丁应用失败（上游结构可能已变）"
    exit 1
}
echo ">>> Mint 模板 ucode 兼容补丁已应用（export default 风格）"
# clone_required "https://github.com/nikkinikki-org/OpenWrt-nikki.git" "package/new/nikki" "luci-app-nikki"  # 已注释：不再使用

# ---- Mihomo 格式 geodata（来自 MetaCubeX/meta-rules-dat）----
# 关键：Clashoo 基于 Mihomo 内核，需要 MetaCubeX 格式的 geodata！
# 不能用 V2Ray 格式（/usr/share/v2ray/geosite.dat）混用，否则报：
#   "list cn not found" / "proto: cannot parse invalid wire-format data"
#
# 各组件 geodata 分布：
#   /etc/nikki/run/GeoSite.dat    → Mihomo 格式（MetaCubeX）         → Nikki  # 已注释
#   /etc/clashoo/GeoSite.dat      → Mihomo 格式（MetaCubeX）         → Clashoo
#   /usr/share/daed/geosite.dat   → daed 自带                        → Daed  # 已注释
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

# 将默认主题改为 mint（克隆失败则保留 OpenWrt 自带的 bootstrap）
if [ -d package/new/luci-theme-mint ]; then
    sed -i 's|/luci-static/bootstrap|/luci-static/mint|g' feeds/luci/modules/luci-base/root/etc/config/luci
    echo ">>> 默认主题已改为 luci-theme-mint"
else
    echo "!!! 警告：Mint 主题不可用，默认保留 luci-theme-bootstrap"
fi

# 默认语言固定为简体中文（需配合 seed 里的 CONFIG_LUCI_LANG_zh_Hans 全局开关）
LUCI_CFG="feeds/luci/modules/luci-base/root/etc/config/luci"
if [ -f "$LUCI_CFG" ]; then
    if grep -q 'option lang' "$LUCI_CFG"; then
        sed -i 's/^\([[:space:]]*option lang \).*/\1zh_cn/' "$LUCI_CFG"
    else
        sed -i '/^config core/a\\toption lang zh_cn' "$LUCI_CFG"
    fi
    echo ">>> LuCI 默认语言已设为 zh_cn"
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
