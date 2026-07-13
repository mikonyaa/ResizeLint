#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
scanner="$repository_root/Scripts/ci/public-artifact-scan.sh"

if [[ ! -x "$scanner" ]]; then
  echo "Publication scanner is missing or not executable: $scanner" >&2
  exit 1
fi

fixture=$(mktemp -d "${TMPDIR:-/tmp}/resizelint-public-scan.XXXXXX")
trap 'rm -rf "$fixture"' EXIT

git -C "$fixture" init -q
cp "$scanner" "$fixture/public-artifact-scan.sh"
printf '%s\n' '# Clean project' > "$fixture/README.md"
git -C "$fixture" add README.md public-artifact-scan.sh

(cd "$fixture" && ./public-artifact-scan.sh)

printf '%s\n' "open""ai" > "$fixture/Leak.md"
git -C "$fixture" add Leak.md
if (cd "$fixture" && ./public-artifact-scan.sh >/dev/null 2>&1); then
  echo "Publication scanner accepted a forbidden internal marker" >&2
  exit 1
fi

rm "$fixture/Leak.md"
git -C "$fixture" add -u
printf '%s\n' "/""Users/example/private" > "$fixture/Leak.md"
git -C "$fixture" add Leak.md
if (cd "$fixture" && ./public-artifact-scan.sh >/dev/null 2>&1); then
  echo "Publication scanner accepted an absolute local path" >&2
  exit 1
fi

echo "Publication scanner self-test passed."
