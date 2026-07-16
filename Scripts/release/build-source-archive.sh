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
staging="$temporary_root/staging"
mkdir -p "$staging/$prefix"

(
  cd "$repository_root"
  git checkout-index -a --prefix="$staging/$prefix/"
)

rm -rf \
  "$staging/$prefix/.build" \
  "$staging/$prefix/.github" \
  "$staging/$prefix/Artifacts" \
  "$staging/$prefix/Formula"

find "$staging/$prefix" -exec touch -h -t 200001010000 {} +
listing="$temporary_root/files.txt"
(
  cd "$staging"
  LC_ALL=C find "$prefix" -print | LC_ALL=C sort > "$listing"
)

uncompressed="$temporary_root/source.tar"
tar_options=(
  --format=ustar
  --uid 0
  --gid 0
  --uname root
  --gname root
  --no-acls
  --no-xattrs
)
if tar --version 2>/dev/null | grep -q 'bsdtar'; then
  tar_options+=(--no-fflags --no-mac-metadata)
fi

tar -cf "$uncompressed" \
  "${tar_options[@]}" \
  -C "$staging" \
  -T "$listing"

archive="$destination/ResizeLint-$version-source.tar.gz"
gzip -9 -n -c "$uncompressed" > "$archive"
printf '%s\n' "$archive"
