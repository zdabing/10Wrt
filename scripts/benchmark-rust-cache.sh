#!/usr/bin/env bash
# Artifact-only R5C cold/warm comparison; run in the benchmark checkout.
set -euo pipefail
mode=${1:?cold or warm}
root=${GITHUB_WORKSPACE:?}
zen="$root/zen-cache-benchmark"
out="$zen/acceptance-out"
jobs=${BUILD_JOBS:-$(nproc)}
case "$mode" in
  cold)
    git init "$zen"
    git -C "$zen" remote add origin https://github.com/zdabing/luci-zen.git
    git -C "$zen" fetch --depth=1 origin e90ca07334cb8bf7e47787955bd1e8b1424566ed
    git -C "$zen" checkout --detach FETCH_HEAD
    cd "$zen"
    # Inject cache setup and an explicit Rust phase into the pinned fixture.
    # Keep original toolchain/configuration/package-build behavior otherwise.
    python3 - <<'PY'
import os
from pathlib import Path
p=Path('tools/r5c-acceptance-build.sh');source=p.read_text()
assert source.count('phase tools/compile')==1
source=source.replace('phase tools/compile', 'python3 "$GITHUB_WORKSPACE/scripts/rust-dist-cache.py" prepare "$PWD" "$GITHUB_WORKSPACE/rust-dist-cache" > "$out/rust-cache-key.txt"\nphase tools/compile')
assert source.count('phase package/zen-traffic/compile')==1
source=source.replace('phase package/zen-traffic/compile', 'phase package/feeds/packages/rust/host/compile\nphase package/zen-traffic/compile')
Path('tools/cache-fixture-build.sh').write_text(source)
PY
    bash tools/cache-fixture-build.sh
    cat "$out/rust-cache-key.txt" >> "$GITHUB_OUTPUT"
    # Natural host clean removes the installed compiler and its build outputs.
    cd acceptance-openwrt
    make package/feeds/packages/rust/host/clean V=s > "$out/rust-clean.log" 2>&1
    cd "$root"
    ;;
  warm)
    cd "$zen/acceptance-openwrt"
    printf 'phase\tseconds\n' > "$out/warm-build-timings.tsv"
    start=$(date +%s)
    make package/feeds/packages/rust/host/compile -j"$jobs" V=s 2>&1 | tee "$out/rust-warm.log"
    seconds=$(( $(date +%s)-start ))
    printf 'rust/host\t%s\n' "$seconds" >> "$out/warm-build-timings.tsv"
    grep -qF 'Verified OpenWrt Rust distribution cache hit' "$out/rust-warm.log"
    make package/zen-traffic/clean V=s > "$out/zen-warm-clean.log" 2>&1
    start=$(date +%s)
    make package/zen-traffic/compile -j"$jobs" V=s 2>&1 | tee "$out/zen-warm.log"
    printf 'zen-traffic\t%s\n' "$(( $(date +%s)-start ))" >> "$out/warm-build-timings.tsv"
    mapfile -t packages < <(find bin/packages -type f -name 'zen-traffic-0.2.0-r3.apk')
    test "${#packages[@]}" -eq 1
    cp "${packages[0]}" "$out/"
    (cd "$out" && sha256sum ./*.apk > SHA256SUMS && sha256sum -c SHA256SUMS)
    {
      printf '\n### Verified Rust cache comparison\n\n'
      printf 'Same pinned R5C SDK/configuration. Warm time includes archive verification, temporary compiler installation, host execution, target linking and normal Host/Install.\n\n'
      printf '| Rust source build seconds | Cache rebuild seconds |\n| --- | --- |\n'
      cold=$(awk -F '\t' '$1=="package/feeds/packages/rust/host/compile" && $6==0 {print $5; exit}' "$out/build-timings.tsv")
      printf '| %s | %s |\n' "$cold" "$seconds"
    } >> "$GITHUB_STEP_SUMMARY"
    ;;
  *) exit 2 ;;
esac
