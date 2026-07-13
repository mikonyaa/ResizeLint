#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
checker="$repository_root/Scripts/ci/check-doc-links.sh"

if [[ ! -x "$checker" ]]; then
  echo "Documentation link checker is missing or not executable: $checker" >&2
  exit 1
fi

fixture=$(mktemp -d "${TMPDIR:-/tmp}/resizelint-doc-links.XXXXXX")
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/Docs"
printf '%s\n' '# Guide' > "$fixture/Docs/Guide.md"
printf '%s\n' '[Guide](Docs/Guide.md)' > "$fixture/README.md"
"$checker" "$fixture"

printf '%s\n' '[Missing](Docs/Missing.md)' > "$fixture/README.md"
if "$checker" "$fixture" >/dev/null 2>&1; then
  echo "Documentation link checker accepted a missing local target" >&2
  exit 1
fi

echo "Documentation link checker self-test passed."
