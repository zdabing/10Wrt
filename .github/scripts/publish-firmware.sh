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
assets=("$firmware_dir"/*.img.gz "$firmware_dir"/*.img "$firmware_dir"/*.tar.gz)
if ((${#assets[@]} == 0)); then
  echo "No firmware files in $firmware_dir; refusing to publish an empty release" >&2
  exit 1
fi

# Capture one instant for the tag, title and annotated tag date, including
# builds crossing midnight. Numeric version fields have no leading zeroes.
epoch=$(date +%s)
version_date=$(TZ=UTC-8 date -d "@$epoch" +'%Y.%-m.%-d')
clock=$(TZ=UTC-8 date -d "@$epoch" +%H%M%S)
display_date=$(TZ=UTC-8 date -d "@$epoch" +'%Y-%m-%d %H:%M:%S')
tag_date=$(date -u -d "@$epoch" +'%Y-%m-%dT%H:%M:%SZ')
tag="v${version_date}-t${clock}-immortalwrt-${device}-${GITHUB_RUN_NUMBER}-${GITHUB_RUN_ATTEMPT}"
title="10Wrt ImmortalWrt ${device_title} — ${display_date} (UTC+8) · #${GITHUB_RUN_NUMBER}.${GITHUB_RUN_ATTEMPT}"

# Lightweight tags inherit the source commit date for release ordering.
# Annotated tags retain the source SHA but date the release at build completion.
tag_sha=$(gh api --method POST "repos/$GITHUB_REPOSITORY/git/tags" \
  -f tag="$tag" -f message="$title" -f object="$GITHUB_SHA" -f type=commit \
  -f 'tagger[name]=github-actions[bot]' \
  -f 'tagger[email]=41898282+github-actions[bot]@users.noreply.github.com' \
  -f "tagger[date]=$tag_date" --jq .sha)
gh api --method POST "repos/$GITHUB_REPOSITORY/git/refs" \
  -f "ref=refs/tags/$tag" -f sha="$tag_sha" >/dev/null

notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
cat > "$notes" <<EOF
### 管理地址: http://10.0.0.1

- 构建完成时间：${display_date}（UTC+8）
- 配置源码提交：${GITHUB_SHA}
- 构建记录：https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}
EOF
gh release create "$tag" "${assets[@]}" --verify-tag \
  --title "$title" --notes-file "$notes" --latest --repo "$GITHUB_REPOSITORY"
printf '\n### 已发布固件\n\n[%s](https://github.com/%s/releases/tag/%s)\n' \
  "$title" "$GITHUB_REPOSITORY" "$tag" >> "$GITHUB_STEP_SUMMARY"
