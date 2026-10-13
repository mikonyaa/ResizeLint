#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
temporary=$(mktemp -d "${TMPDIR:-/tmp}/resizelint-linux-mock.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
printf '%s\n' '#!/bin/sh' 'echo 1.0.0' > "$temporary/resizelint"
if python3 "$root/Scripts/release/verify-linux-elf.py" "$temporary/resizelint" >/dev/null 2>&1; then
  echo "Linux release verifier accepted a mocked shell executable" >&2
  exit 1
fi
echo "Mock shell executable rejected. Real archive validation is test-linux-release-consumer.sh."
