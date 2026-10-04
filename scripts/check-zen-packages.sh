#!/usr/bin/env bash
# 在 defconfig 后及固件构建后检查 Zen，避免软件包被静默丢弃。
set -euo pipefail

mode=${1:?用法: check-zen-packages.sh <config|installed> <文件>}
file=${2:?缺少配置文件或软件包数据库}
case "$mode" in
    config|installed) ;;
    *) echo "错误：未知检查模式：$mode" >&2; exit 1 ;;
esac
[ -f "$file" ] || { echo "错误：找不到检查文件：$file" >&2; exit 1; }

content=$(tr -d '\r' < "$file")
packages=(luci-theme-zen zen-traffic luci-app-zen-traffic kmod-sched-core kmod-sched-bpf)
missing=()
for package in "${packages[@]}"; do
    if [ "$mode" = config ]; then
        grep -qxF "CONFIG_PACKAGE_${package}=y" <<< "$content" || missing+=("$package")
    elif ! grep -qxF "P:${package}" <<< "$content" &&
         ! grep -qxF "Package: ${package}" <<< "$content"; then
        missing+=("$package")
    fi
done
if (( ${#missing[@]} > 0 )); then
    echo "错误：Zen ${mode} 检查缺少以下软件包：" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    exit 1
fi
echo "Zen ${mode} 检查通过：${#packages[@]} 个软件包"
