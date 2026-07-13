#!/usr/bin/env bash

set -euo pipefail

repository_root=$(git rev-parse --show-toplevel)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/resizelint-clean-room.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT

clone="$temporary_root/ResizeLint"
git clone --quiet --no-local "$repository_root" "$clone"

if [[ -e "$clone/.build" ]]; then
  echo "Clean clone unexpectedly contains build products" >&2
  exit 1
fi

cd "$clone"
swift package resolve
swift build
swift test

echo "Clean-room resolve, build, and test passed."
