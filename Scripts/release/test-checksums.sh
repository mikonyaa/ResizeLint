#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
generator="$repository_root/Scripts/release/checksums.sh"

if [[ ! -x "$generator" ]]; then
  echo "Checksum generator is missing or not executable: $generator" >&2
  exit 1
fi

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/resizelint-checksums-test.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT

printf '%s\n' 'macOS fixture' > "$temporary_root/ResizeLint-1.0.0-macos-universal.zip"
printf '%s\n' 'Linux fixture' > "$temporary_root/ResizeLint-1.0.0-linux-x86_64.tar.gz"

"$generator" "$temporary_root"
(cd "$temporary_root" && shasum -a 256 -c SHA256SUMS)

if [[ $(wc -l < "$temporary_root/SHA256SUMS" | tr -d ' ') -ne 2 ]]; then
  echo "Checksum manifest has an unexpected entry count" >&2
  exit 1
fi

echo "Checksum generator self-test passed."
