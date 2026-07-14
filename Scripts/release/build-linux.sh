#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
destination=${1:-"$repository_root/Artifacts"}
version=${2:-1.0.0}

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required for the Linux release build" >&2
  exit 2
fi

mkdir -p "$destination"
destination=$(cd "$destination" && pwd -P)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/resizelint-linux-build.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
chmod 0777 "$scratch"

docker run --rm \
  --platform linux/amd64 \
  --user "$(id -u):$(id -g)" \
  --volume "$repository_root:/workspace:ro" \
  --volume "$scratch:/build" \
  --workdir /workspace \
  --env HOME=/tmp \
  swift:6.3.3-jammy \
  swift build --configuration release --scratch-path /build

binary=$(find "$scratch" -type f -path '*/release/resizelint' -perm -111 -print -quit)
if [[ -z "$binary" ]]; then
  echo "Linux release binary was not produced" >&2
  exit 1
fi

staging="$scratch/staging"
mkdir -p "$staging"
install -m 0755 "$binary" "$staging/resizelint"
touch -t 200001010000 "$staging/resizelint"

archive="$destination/ResizeLint-$version-linux-x86_64.tar.gz"
tar_options=(--no-acls --no-xattrs)
if tar --version 2>/dev/null | grep -q 'bsdtar'; then
  tar_options+=(--no-fflags --no-mac-metadata)
fi

COPYFILE_DISABLE=1 tar -czf "$archive" \
  "${tar_options[@]}" \
  -C "$staging" \
  resizelint

printf '%s\n' "$archive"
