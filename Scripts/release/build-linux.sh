#!/usr/bin/env bash
set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
destination=${1:-"$repository_root/Artifacts"}
version=${2:-1.0.1-rc.1}
sdk_url=https://download.swift.org/swift-6.3.3-release/static-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_static-linux-0.1.0.artifactbundle.tar.gz
sdk_checksum=87c3eaf908e67c0e13a84367119e12273cec1d2cd3d81f7d74bb36722d6b607b

if ! command -v docker >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  echo "Docker and Python 3 are required for the Linux release build" >&2
  exit 2
fi
mkdir -p "$destination"
destination=$(cd "$destination" && pwd -P)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/resizelint-linux-build.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
chmod 0777 "$scratch"
source_tree=$(git -C "$repository_root" write-tree)
mkdir -p "$scratch/source"
git -C "$repository_root" archive --format=tar "$source_tree" > "$scratch/source.tar"
tar -xf "$scratch/source.tar" -C "$scratch/source"
printf 'Building indexed source tree %s\n' "$source_tree"

# The matching SDK statically links Swift, Foundation and musl, including the C runtime.
# All writable SwiftPM/SDK paths belong to this disposable build; the source mount is read-only.
docker run --rm --platform linux/amd64 \
  --user "$(id -u):$(id -g)" \
  --label io.github.mikonyaa.resizelint.build=release-candidate \
  --volume "$scratch/source:/workspace:ro" --volume "$scratch:/build" --workdir /workspace \
  --env RESIZELINT_SDK_URL="$sdk_url" --env RESIZELINT_SDK_CHECKSUM="$sdk_checksum" \
  --env RESIZELINT_EXPECTED_VERSION="$version" \
  --env XDG_CACHE_HOME=/build/xdg-cache \
  --env CLANG_MODULE_CACHE_PATH=/build/clang-module-cache \
  --env SWIFT_MODULECACHE_PATH=/build/swift-module-cache \
  swift:6.3.3-jammy bash -c '
    set -euo pipefail
    swift --version
    swift sdk install --swift-sdks-path /build/sdks "$RESIZELINT_SDK_URL" --checksum "$RESIZELINT_SDK_CHECKSUM"
    swift build --configuration release --swift-sdk x86_64-swift-linux-musl \
      --swift-sdks-path /build/sdks --scratch-path /build/output --cache-path /build/cache \
      --config-path /build/config --security-path /build/security --jobs 4
    binary=/build/output/x86_64-swift-linux-musl/release/resizelint
    test "$("$binary" version)" = "$RESIZELINT_EXPECTED_VERSION"
  '

binary="$scratch/output/x86_64-swift-linux-musl/release/resizelint"
python3 "$repository_root/Scripts/release/verify-linux-elf.py" "$binary"
staging="$scratch/staging"
mkdir -p "$staging"
install -m 0755 "$binary" "$staging/resizelint"
TZ=UTC touch -t 200001010000 "$staging/resizelint"
archive="$destination/ResizeLint-$version-linux-x86_64.tar.gz"
tar_options=(--no-acls --no-xattrs)
if tar --version 2>/dev/null | grep -q 'bsdtar'; then
  tar_options+=(--no-fflags --no-mac-metadata --uid 0 --gid 0 --uname root --gname root)
else
  tar_options+=(--owner=0 --group=0 --numeric-owner)
fi
COPYFILE_DISABLE=1 tar -cf "$scratch/linux.tar" "${tar_options[@]}" -C "$staging" resizelint
gzip -9 -n -c "$scratch/linux.tar" > "$archive"
printf '%s\n' "$archive"
