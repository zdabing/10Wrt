#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
    x86_64)
        device_symbol=CONFIG_TARGET_x86_64_DEVICE_generic
        firmware_target=x86/64
        cache_suffix=x86
        target_label='x86/64'
        ;;
    r5c)
        device_symbol=CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r5c
        firmware_target=rockchip/armv8
        cache_suffix=r5c
        target_label='NanoPi R5C'
        ;;
    *)
        echo "错误：未知构建目标：${1:-<empty>}" >&2
        exit 1
        ;;
esac

printf 'BUILD_TARGET=%s\n' "$1"
printf 'SEED_PATH=config/configs/%s.seed\n' "$1"
printf 'DEVICE_SYMBOL=%s\n' "$device_symbol"
printf 'FIRMWARE_TARGET=%s\n' "$firmware_target"
printf 'CACHE_SUFFIX=%s\n' "$cache_suffix"
printf 'TARGET_LABEL=%s\n' "$target_label"
