#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
destination=${1:-"$repository_root/Artifacts/macos-builds"}
mkdir -p "$destination"
destination=$(cd "$destination" && pwd -P)

scratch=$(mktemp -d "${TMPDIR:-/tmp}/resizelint-macos-build.XXXXXX")
trap 'rm -rf "$scratch"' EXIT

cd "$repository_root"
swift package resolve

for architecture in arm64 x86_64; do
  triple="$architecture-apple-macosx14.0"
  swift build \
    --configuration release \
    --scratch-path "$scratch/$architecture" \
    --triple "$triple"

  binary=$(find "$scratch/$architecture" -type f -path '*/release/resizelint' -perm -111 -print -quit)
  if [[ -z "$binary" ]]; then
    echo "Release binary was not produced for $architecture" >&2
    exit 1
  fi

  mkdir -p "$destination/$architecture"
  install -m 0755 "$binary" "$destination/$architecture/resizelint"
done

if [[ $(lipo -archs "$destination/arm64/resizelint") != "arm64" ]]; then
  echo "arm64 build has an unexpected architecture" >&2
  exit 1
fi
if [[ $(lipo -archs "$destination/x86_64/resizelint") != "x86_64" ]]; then
  echo "x86_64 build has an unexpected architecture" >&2
  exit 1
fi

"$destination/arm64/resizelint" version
printf '%s\n' "$destination"
