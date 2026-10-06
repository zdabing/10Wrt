#!/usr/bin/env bash
# 在 OpenWrt 根目录执行；顶层 world 管理依赖和全部构建产物。
set -euo pipefail
jobs=${BUILD_JOBS:-$(nproc)}

if ! make world -j"$jobs" V=s 2>&1 | tee -a build.log; then
    echo '并行编译失败，使用单线程重试以定位错误' | tee -a build.log
    make world -j1 V=s 2>&1 | tee -a build.log
fi
