#!/usr/bin/env bash
# 在长时间固件编译前检查 OpenWrt 主机 LLVM 配置和完整 eBPF 编译链。
set -euo pipefail

prefix=${1:-/usr}
config=${2:-}

fail() {
    echo "错误：$*" >&2
    echo '请安装同一版本的 clang 和 llvm，并确认 BPF_TOOLCHAIN_HOST_PATH 指向其 bin 的上级目录。' >&2
    if [ "${GITHUB_ACTIONS:-}" = true ]; then
        echo "::error title=eBPF 工具链检查失败::$*"
    fi
    exit 1
}

if [ -n "$config" ]; then
    [ -f "$config" ] || fail "找不到 OpenWrt 配置：$config"
    # seed 来自 Windows 时也接受 CRLF。
    config_text=$(tr -d '\r' < "$config")
    for symbol in CONFIG_BPF_TOOLCHAIN_HOST=y CONFIG_USE_LLVM_HOST=y; do
        grep -qxF "$symbol" <<< "$config_text" ||
            fail "$symbol 未生效；OpenWrt 可能退回 /invalid/clang。请检查 make defconfig 的结果。"
    done
    configured_prefix=$(sed -n 's/^CONFIG_BPF_TOOLCHAIN_HOST_PATH="\(.*\)"$/\1/p' <<< "$config_text")
    [ "$configured_prefix" = "$prefix" ] ||
        fail "OpenWrt 的 LLVM 路径为 ${configured_prefix:-<未设置>}，本次检查路径为 $prefix。"
fi

tools=(clang llc llvm-dis opt llvm-strip)
major_version=
for tool in "${tools[@]}"; do
    tool_path="$prefix/bin/$tool"
    [ -x "$tool_path" ] || fail "缺少可执行工具：$tool_path"
    version_output=$("$tool_path" --version 2>&1) || fail "无法运行 $tool_path：$version_output"
    version=$(sed -nE 's/.*version ([0-9]+)\..*/\1/p' <<< "$version_output" | head -n 1)
    [[ "$version" =~ ^[0-9]+$ ]] || fail "无法识别 $tool_path 的版本：$version_output"
    [ "$version" -ge 12 ] || fail "$tool_path 版本为 $version，OpenWrt eBPF 至少需要 LLVM 12。"
    if [ -n "$major_version" ] && [ "$version" != "$major_version" ]; then
        fail "$tool_path 为 LLVM $version，其他工具为 LLVM $major_version；混用版本可能无法读取 bitcode。"
    fi
    major_version=$version
    echo "已检查 $tool_path：LLVM $version"
done

probe_dir=$(mktemp -d)
trap 'rm -rf "$probe_dir"' EXIT
cat > "$probe_dir/probe.c" <<'EOF'
__attribute__((section("classifier")))
int bpf_probe(void *ctx) { return 0; }
char bpf_probe_license[] __attribute__((section("license"), used)) = "GPL";
EOF

probe_step() {
    local label=$1
    shift
    if ! "$@" 2> "$probe_dir/error.log"; then
        cat "$probe_dir/error.log" >&2
        fail "$label 失败；详细错误见上方。尚未进入固件编译。"
    fi
}

# 对应 OpenWrt CompileBPF 的 clang → opt → llvm-dis → llc → strip 链路。
probe_step 'Clang 生成 BPF bitcode' "$prefix/bin/clang" -O2 -g -target bpfel-linux-gnu \
    -emit-llvm -Xclang -disable-llvm-passes -c "$probe_dir/probe.c" -o "$probe_dir/probe.bc"
probe_step 'LLVM 优化 BPF bitcode' "$prefix/bin/opt" -O2 -mtriple=bpfel \
    "$probe_dir/probe.bc" -o "$probe_dir/probe.opt"
probe_step 'LLVM 读取优化后的 bitcode' "$prefix/bin/llvm-dis" \
    "$probe_dir/probe.opt" -o "$probe_dir/probe.ll"
probe_step 'LLVM 生成 BPF 对象' "$prefix/bin/llc" -march=bpfel -mcpu=v3 -filetype=obj \
    "$probe_dir/probe.ll" -o "$probe_dir/probe.o"
probe_step 'LLVM 裁剪 BPF 调试信息' "$prefix/bin/llvm-strip" --strip-debug "$probe_dir/probe.o"
[ -s "$probe_dir/probe.o" ] || fail 'LLVM 未生成有效的 BPF 对象文件。'

echo "eBPF 工具链检查通过：LLVM $major_version，路径 $prefix，完整 BPF 编译链可用。"
