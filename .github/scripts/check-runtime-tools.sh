#!/usr/bin/env bash
# Build-time checks only; never execute target binaries on the CI host.
set -euo pipefail

root=${1:?用法: check-runtime-tools.sh <源码目录> [--config-only]}
mode=${2:-image}
case "$mode" in image|--config-only) ;; *) echo '错误：未知检测模式' >&2; exit 1 ;; esac
[[ -d "$root" ]] || { echo "错误：源码目录不存在：$root" >&2; exit 1; }

applets=(SLEEP FLOAT_DURATION FEATURE_FANCY_SLEEP NC NC_EXTRA NC_110_COMPAT
    NSLOOKUP FEATURE_NSLOOKUP_BIG LONG_OPTS FEATURE_NSLOOKUP_LONG_OPTIONS
    TIMEOUT STAT FEATURE_STAT_FORMAT FLOCK OD)
packages=(busybox curl ca-bundle gzip coreutils-sha256sum yq ucode
    ucode-mod-fs ucode-mod-uci unzip ip-full iperf3 kmod-nft-socket kmod-tcp-bbr)

require_yes() {
    local file=$1 symbol=$2
    if ! grep -qxF "$symbol=y" "$file" && ! grep -qxF "$symbol=y"$'\r' "$file"; then
        echo "错误：$file 缺少 $symbol=y" >&2
        return 1
    fi
}

[[ -f "$root/.config" ]] || { echo '错误：没有展开后的 .config' >&2; exit 1; }
require_yes "$root/.config" CONFIG_BUSYBOX_CUSTOM
for symbol in "${applets[@]}"; do require_yes "$root/.config" "CONFIG_BUSYBOX_CONFIG_$symbol"; done
for package in "${packages[@]}"; do require_yes "$root/.config" "CONFIG_PACKAGE_$package"; done
echo 'BusyBox 功能和插件工具的固件配置检查通过'
[[ "$mode" != --config-only ]] || exit 0

# Check the actual BusyBox compilation config as well as the outer Kconfig.
# A seed entry alone does not prove that the generated binary contains it.
mapfile -d '' -t configs < <(find "$root/build_dir" -type f -path '*/target-*/busybox-*/.config' -print0)
(( ${#configs[@]} == 1 )) || { echo '错误：缺少或存在多份 BusyBox 编译配置' >&2; exit 1; }
for symbol in "${applets[@]}"; do require_yes "${configs[0]}" "CONFIG_$symbol"; done

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
echo 'BusyBox 实际编译配置和固件软件包清单检查通过'
