#!/usr/bin/env bash

set -euo pipefail

SEED=${1:?用法: validate-seed-packages.sh <seed> [config]}
CONFIG=${2:-.config}

if [ ! -f "$SEED" ]; then
    echo "错误：seed 文件不存在：$SEED"
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    echo "错误：展开后的配置文件不存在：$CONFIG"
    exit 1
fi

# seed 在 Windows 工作区中可能保留 CRLF，先去掉行尾 CR 再提取配置符号。
mapfile -t REQUIRED_CONFIGS < <(sed -n 's/\r$//; s/^\(CONFIG_PACKAGE_[^=]*\)=y$/\1/p' "$SEED")
MISSING_CONFIGS=()

for SYMBOL in "${REQUIRED_CONFIGS[@]}"; do
    if ! grep -qxF "${SYMBOL}=y" "$CONFIG" &&
       ! grep -qxF "${SYMBOL}=y"$'\r' "$CONFIG"; then
        MISSING_CONFIGS+=("$SYMBOL")
    fi
done

if (( ${#MISSING_CONFIGS[@]} > 0 )); then
    echo "错误：以下 seed 软件包未在 defconfig 后保留："
    printf '  - %s\n' "${MISSING_CONFIGS[@]}"
    exit 1
fi

echo "seed 软件包配置验证通过：${#REQUIRED_CONFIGS[@]} 项"
