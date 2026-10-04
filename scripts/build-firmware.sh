#!/usr/bin/env bash
# Run from the OpenWrt root. Preserve the existing retry policy and record
# enough evidence to distinguish cold toolchain cost from package builds.
set -euo pipefail
jobs=${BUILD_JOBS:-$(nproc)}
timings=build-timings.tsv
printf 'phase\tattempt\tjobs\tstart_unix\tseconds\texit_code\n' > "$timings"

build_phase() {
    local phase=$1
    shift
    local attempt=0 parallel start elapsed code
    for parallel in "$@"; do
        attempt=$((attempt + 1))
        start=$(date +%s)
        if make "$phase" -j"$parallel" V=s 2>&1 | tee -a build.log; then
            code=0
        else
            code=$?
        fi
        elapsed=$(( $(date +%s) - start ))
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$phase" "$attempt" "$parallel" "$start" "$elapsed" "$code" >> "$timings"
        if (( code == 0 )); then
            return 0
        fi
    done
    return "$code"
}

write_summary() {
    if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
        {
            printf '\n### 编译阶段耗时（包含失败重试）\n\n'
            printf '| 阶段 | 尝试 | 并行数 | 秒数 | 退出码 |\n| --- | --- | --- | --- | --- |\n'
            awk -F '\t' 'NR > 1 { printf "| %s | %s | %s | %s | %s |\n", $1, $2, $3, $5, $6 }' "$timings"
        } >> "$GITHUB_STEP_SUMMARY"
    fi
}
trap write_summary EXIT

build_phase tools/compile "$jobs" "$jobs" 1
build_phase toolchain/compile "$jobs" "$jobs" 1
build_phase target/compile "$jobs" 1
build_phase package/compile "$jobs" 1
build_phase package/index 1
build_phase package/install "$jobs" 1
build_phase target/install "$jobs" 1
# target/install 仅生成每张镜像的 JSON；profiles.json 由顶层目标汇总。
build_phase json_overview_image_info 1
