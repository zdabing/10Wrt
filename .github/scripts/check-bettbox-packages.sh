#!/usr/bin/env bash
# Verify that Bettbox core and LuCI packages survive defconfig and image packaging.
set -euo pipefail

root=${1:?用法: check-bettbox-packages.sh <源码目录> [--config-only]}
mode=${2:-image}
case "$mode" in image|--config-only) ;; *) echo '错误：未知检测模式' >&2; exit 1 ;; esac
[[ -d "$root" ]] || { echo "错误：源码目录不存在：$root" >&2; exit 1; }

packages=(bettbox luci-app-bettbox)

require_yes() {
    local file=$1 symbol=$2
    if ! grep -qxF "$symbol=y" "$file" && ! grep -qxF "$symbol=y"$'\r' "$file"; then
        echo "错误：$file 缺少 $symbol=y" >&2
        return 1
    fi
}

[[ -f "$root/.config" ]] || { echo '错误：没有展开后的 .config' >&2; exit 1; }
for package in "${packages[@]}"; do
    require_yes "$root/.config" "CONFIG_PACKAGE_$package"
done
echo 'Bettbox 固件配置检查通过'
[[ "$mode" != --config-only ]] || exit 0

mapfile -d '' -t manifests < <(find "$root/bin/targets" -type f -name '*.manifest' -print0)
(( ${#manifests[@]} > 0 )) || { echo '错误：没有固件安装包清单' >&2; exit 1; }
for manifest in "${manifests[@]}"; do
    for package in "${packages[@]}"; do
        grep -Eq "^${package}([[:space:]]|$)" "$manifest" || {
            echo "错误：$manifest 没有包含 $package，停止发布" >&2
            exit 1
        }
    done
done
echo 'Bettbox 固件软件包清单检查通过'
