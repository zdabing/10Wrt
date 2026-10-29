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

# ---- Node.js 替换为预编译版 ----
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

# ---- 安装 feeds ----
echo ">>> 安装 feeds..."
./scripts/feeds install -a

# ============================================================
# 自定义软件包（按项目放入 package/，由构建系统直接扫描）
# ============================================================

mkdir -p package/custom package/zen

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

clone_or_warn "https://github.com/svenshi/luci-app-oxidns.git" "package/custom/luci-app-oxidns" "luci-app-oxidns"
# 从自有 zdabing/luci-zen 项目导入三个软件包，单独放入 package/zen。
# 这是编译源码目录，不注册为 feed，也不生成虚假的在线 APK 仓库。
ZEN_SOURCE=$(mktemp -d)
git clone --depth 1 --branch main https://github.com/zdabing/luci-zen.git "$ZEN_SOURCE"
for pkg in luci-theme-zen zen-traffic luci-app-zen-traffic; do
    mkdir -p "package/zen/$pkg"
    cp -R "$ZEN_SOURCE/$pkg/." "package/zen/$pkg/"
done
echo ">>> 已集成 Zen 主题与流量统计：$(git -C "$ZEN_SOURCE" rev-parse HEAD)"
rm -rf "$ZEN_SOURCE"

# ---- 默认使用 Zen 主题 ----
sed -i 's|/luci-static/bootstrap|/luci-static/zen|g' feeds/luci/modules/luci-base/root/etc/config/luci
echo ">>> 默认主题已改为 luci-theme-zen"

echo ">>> [diy.sh] 自定义配置完成"
