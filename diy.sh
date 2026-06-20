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

# ---- 移除 SNAPSHOT 标签 ----
sed -i 's,-SNAPSHOT,,g' include/version.mk
sed -i 's,-SNAPSHOT,,g' package/base-files/image-config.in
echo ">>> 固件版本已移除 SNAPSHOT 标签"

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
clone_or_warn "https://github.com/eamonxg/luci-theme-aurora.git"  "package/new/luci-theme-aurora"    "luci-theme-aurora"
clone_or_warn "https://github.com/nikkinikki-org/OpenWrt-nikki.git" "package/new/nikki"    "luci-app-nikki"

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

# ---- luci-app-xray feed ----
XRAY_FEED="src-git-full luci_app_xray https://github.com/yichya/luci-app-xray.git"
if ! grep -qF "$XRAY_FEED" feeds.conf.default; then
    echo "$XRAY_FEED" >> feeds.conf.default
    ./scripts/feeds update luci_app_xray
    ./scripts/feeds install -a -p luci_app_xray
    echo ">>> 已添加 yichya/luci-app-xray 软件源"
else
    echo ">>> luci-app-xray feed 已存在，跳过"
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
