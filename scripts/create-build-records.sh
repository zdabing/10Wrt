#!/usr/bin/env bash
set -euo pipefail

target=${1:?用法: create-build-records.sh <x86/64|rockchip/armv8> <config-commit>}
config_commit=${2:?缺少配置仓库提交号}
firmware_dir="openwrt/bin/targets/$target"
test -d "$firmware_dir" || { echo "错误：未找到固件目录：$firmware_dir" >&2; exit 1; }

shopt -s nullglob
images=("$firmware_dir"/*.img.gz "$firmware_dir"/*.img "$firmware_dir"/*.tar.gz)
((${#images[@]} > 0)) || { echo "错误：固件目录里没有镜像文件" >&2; exit 1; }

for image in "${images[@]}"; do
    case "$image" in
        *.gz)
            gzip_error=$(mktemp)
            if gzip -t "$image" 2>"$gzip_error"; then
                :
            elif grep -q 'decompression OK' "$gzip_error"; then
                # sysupgrade 镜像的 gzip 流后可能附有 fwtool 设备元数据。
                echo "已验证 gzip 数据，尾部含设备元数据：${image##*/}"
            else
                cat "$gzip_error" >&2
                rm -f "$gzip_error"
                echo "错误：压缩镜像校验失败：$image" >&2
                exit 1
            fi
            rm -f "$gzip_error"
            ;;
    esac
done

(cd "$firmware_dir" && sha256sum "${images[@]##*/}" > SHA256SUMS && sha256sum -c SHA256SUMS --quiet)

package_db=$(find openwrt/build_dir -type f \( \
    -path '*/root-*/lib/apk/db/installed' -o \
    -path '*/root-*/usr/lib/opkg/status' \) -print -quit)
test -n "$package_db" || { echo '错误：未找到固件软件包数据库' >&2; exit 1; }

awk '
    /^P:/ { name=substr($0, 3) }
    /^V:/ { version=substr($0, 3) }
    /^Package: / { name=substr($0, 10) }
    /^Version: / { version=substr($0, 10) }
    /^$/ { if (name != "" && version != "") print name " - " version; name=""; version="" }
    END { if (name != "" && version != "") print name " - " version }
' "$package_db" | LC_ALL=C sort -u > "$firmware_dir/10wrt-packages.manifest"
test -s "$firmware_dir/10wrt-packages.manifest" || {
    echo '错误：软件包清单为空' >&2
    exit 1
}

{
    printf '10Wrt config commit\t%s\n' "$config_commit"
    printf 'OpenWrt source\t%s\t%s\n' "$(git -C openwrt remote get-url origin)" "$(git -C openwrt rev-parse HEAD)"
    for feed in openwrt/feeds/*; do
        test -d "$feed/.git" || continue
        printf 'feed/%s\t%s\t%s\n' "${feed##*/}" "$(git -C "$feed" remote get-url origin)" "$(git -C "$feed" rev-parse HEAD)"
    done
    if test -f openwrt/package/new/.source-revisions.tsv; then
        cat openwrt/package/new/.source-revisions.tsv
    fi
} > "$firmware_dir/10wrt-sources.tsv"

echo "镜像校验值、软件包清单和源码版本已写入 $firmware_dir"
