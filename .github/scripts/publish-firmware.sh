#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

device=${1:?Expected r5c or x86_64}
firmware_dir=${2:?Expected firmware directory}
case "$device" in
  r5c) device_title='NanoPi R5C' ;;
  x86_64) device_title='x86/64' ;;
  *) echo "Unsupported device: $device" >&2; exit 1 ;;
esac
assets=("$firmware_dir"/*.img.gz "$firmware_dir"/*.img)
for file in "$firmware_dir"/*.tar.gz; do
  [[ "${file##*/}" = zen-support.tar.gz ]] || assets+=("$file")
done
if ((${#assets[@]} == 0)); then
  echo "No firmware files in $firmware_dir; refusing to publish an empty release" >&2
  exit 1
fi

# Record build completion in the release title and notes.
# The tag name was already stamped into the firmware before image generation.
epoch=$(date +%s)
display_date=$(TZ=UTC-8 date -d "@$epoch" +'%Y-%m-%d %H:%M:%S')
tag=${FIRMWARE_TAG:?Expected the tag stamped into the firmware identity}
title="10Wrt OpenWrt ${device_title} — ${display_date} (UTC+8) · #${GITHUB_RUN_NUMBER}.${GITHUB_RUN_ATTEMPT}"

# Keep the existing firmware identity, checksums and update metadata together.
if [[ -f "$firmware_dir/zen-support.tar.gz" ]]; then
  assets+=("$firmware_dir/zen-support.tar.gz" "$firmware_dir/zen-support.json")
fi

for name in SHA256SUMS 10wrt-packages.manifest 10wrt-sources.tsv 10wrt-update.json 10wrt-update-notes.md; do
  test -s "$firmware_dir/$name"
done
assets+=("$firmware_dir/SHA256SUMS" "$firmware_dir/10wrt-packages.manifest"
         "$firmware_dir/10wrt-sources.tsv" "$firmware_dir/10wrt-update.json")

notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
cat > "$notes" <<EOF
### 管理地址: http://10.0.0.1

- 构建完成时间：${display_date}（UTC+8）
- 配置源码提交：${GITHUB_SHA}
- 构建记录：https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}
EOF
cat "$firmware_dir/10wrt-update-notes.md" >> "$notes"
# Let the release API create the tag at the exact configuration commit.
# Cleanup sorts by published_at; it does not require an annotated tag date.
gh release create "$tag" "${assets[@]}" --target "$GITHUB_SHA" \
  --title "$title" --notes-file "$notes" --latest --repo "$GITHUB_REPOSITORY"
printf '\n### 已发布固件\n\n[%s](https://github.com/%s/releases/tag/%s)\n' \
  "$title" "$GITHUB_REPOSITORY" "$tag" >> "$GITHUB_STEP_SUMMARY"
