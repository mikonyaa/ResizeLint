#!/usr/bin/env bash

set -euo pipefail

input=${1:-}
destination=${2:-}
version=${3:-1.0.0}
mode=${4:-unsigned}

if [[ -z "$input" || -z "$destination" ]]; then
  echo "Usage: $0 <macos-build-directory> <artifact-directory> [version] [unsigned|--sign]" >&2
  exit 2
fi
if [[ "$mode" != "unsigned" && "$mode" != "--sign" ]]; then
  echo "Unsupported assembly mode: $mode" >&2
  exit 2
fi

arm64_binary="$input/arm64/resizelint"
x86_binary="$input/x86_64/resizelint"
if [[ ! -x "$arm64_binary" || ! -x "$x86_binary" ]]; then
  echo "Both arm64 and x86_64 release binaries are required" >&2
  exit 2
fi

mkdir -p "$destination"
destination=$(cd "$destination" && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/resizelint-macos-artifact.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT

universal="$temporary_root/resizelint"
lipo -create "$arm64_binary" "$x86_binary" -output "$universal"
chmod 0755 "$universal"

architectures=$(lipo -archs "$universal")
if [[ "$architectures" != *arm64* || "$architectures" != *x86_64* ]]; then
  echo "Universal binary is missing an architecture: $architectures" >&2
  exit 1
fi

if [[ "$mode" == "--sign" ]]; then
  : "${RESIZELINT_APPLICATION_IDENTITY:?RESIZELINT_APPLICATION_IDENTITY is required}"
  : "${RESIZELINT_INSTALLER_IDENTITY:?RESIZELINT_INSTALLER_IDENTITY is required}"
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$RESIZELINT_APPLICATION_IDENTITY" \
    "$universal"
  codesign --verify --strict --verbose=2 "$universal"
fi

zip_path="$destination/ResizeLint-$version-macos-universal.zip"
COPYFILE_DISABLE=1 zip -X -q -j "$zip_path" "$universal"

package_root="$temporary_root/package-root"
mkdir -p "$package_root/usr/local/bin"
install -m 0755 "$universal" "$package_root/usr/local/bin/resizelint"
package_path="$destination/ResizeLint-$version-macos-universal.pkg"
package_arguments=(
  --root "$package_root"
  --identifier io.github.mikonyaa.resizelint
  --version "$version"
  --install-location /
)
if [[ "$mode" == "--sign" ]]; then
  package_arguments+=(--sign "$RESIZELINT_INSTALLER_IDENTITY")
fi
pkgbuild "${package_arguments[@]}" "$package_path"

install -m 0755 "$universal" "$destination/resizelint-macos-universal"
printf '%s\n%s\n' "$zip_path" "$package_path"
