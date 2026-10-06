#!/usr/bin/env bash
# 在 OpenWrt 根目录执行；失败时重试，最终失败则停止构建。
set -euo pipefail
jobs=${BUILD_JOBS:-$(nproc)}
build_phase() {
    local phase=$1
    shift
    local parallel code
    for parallel in "$@"; do
        if make "$phase" -j"$parallel" V=s 2>&1 | tee -a build.log; then
            code=0
        else
            code=$?
        fi
        if (( code == 0 )); then
            return 0
        fi
    done
    return "$code"
}

build_phase tools/compile "$jobs" "$jobs" 1
build_phase toolchain/compile "$jobs" "$jobs" 1
build_phase target/compile "$jobs" 1
build_phase package/compile "$jobs" 1
build_phase package/index 1
build_phase package/install "$jobs" 1
build_phase target/install "$jobs" 1
# target/install 仅生成每张镜像的 JSON；profiles.json 由顶层目标汇总。
build_phase json_overview_image_info 1
