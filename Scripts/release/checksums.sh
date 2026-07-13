#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

directory=${1:-}
if [[ -z "$directory" || ! -d "$directory" ]]; then
  echo "Usage: $0 <artifact-directory>" >&2
  exit 2
fi

directory=$(cd "$directory" && pwd -P)
artifacts=(
  "$directory"/ResizeLint-*.zip
  "$directory"/ResizeLint-*.pkg
  "$directory"/ResizeLint-*.tar.gz
)

if [[ ${#artifacts[@]} -eq 0 ]]; then
  echo "No ResizeLint release artifacts found in $directory" >&2
  exit 2
fi

temporary="$directory/.SHA256SUMS.tmp.$$"
trap 'rm -f "$temporary"' EXIT
: > "$temporary"

for artifact in "${artifacts[@]}"; do
  name=$(basename "$artifact")
  if command -v shasum >/dev/null 2>&1; then
    digest=$(shasum -a 256 "$artifact" | awk '{ print $1 }')
  else
    digest=$(sha256sum "$artifact" | awk '{ print $1 }')
  fi
  printf '%s  %s\n' "$digest" "$name" >> "$temporary"
done

LC_ALL=C sort -o "$temporary" "$temporary"
mv -f "$temporary" "$directory/SHA256SUMS"
trap - EXIT

printf '%s\n' "$directory/SHA256SUMS"
