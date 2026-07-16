#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
destination=${1:-}
version=${2:-1.0.0}

if [[ -z "$destination" ]]; then
  echo "Usage: $0 <destination-directory> [version]" >&2
  exit 2
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid version: $version" >&2
  exit 2
fi

mkdir -p "$destination"
destination=$(cd "$destination" && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/resizelint-source.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT

prefix="ResizeLint-$version"
uncompressed="$temporary_root/source.tar"
(
  cd "$repository_root"
  tree=$(git write-tree)
  git archive \
    --format=tar \
    --mtime="2000-01-01T00:00:00Z" \
    --prefix="$prefix/" \
    --output="$uncompressed" \
    "$tree" \
    -- \
    . \
    ':(exclude).build' \
    ':(exclude).github' \
    ':(exclude)Artifacts' \
    ':(exclude)Formula'
)

archive="$destination/ResizeLint-$version-source.tar.gz"
gzip -9 -n -c "$uncompressed" > "$archive"
printf '%s\n' "$archive"
