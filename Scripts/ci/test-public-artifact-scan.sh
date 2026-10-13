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

printf '%s\n' 'OpenAI Codex, ChatGPT, Claude, Copilot, prompt, AI-generated and AGENTS.md are permissible documentation.' > "$fixture/Tools.md"
printf '%s\n' '# Contributor instructions' > "$fixture/AGENTS.md"
git -C "$fixture" add Tools.md AGENTS.md
(cd "$fixture" && ./public-artifact-scan.sh)

reject_fixture() {
  if (cd "$fixture" && ./public-artifact-scan.sh >/dev/null 2>&1); then
    echo "Publication scanner accepted $1" >&2
    exit 1
  fi
}
for suffix in p12 p8 mobileprovision; do
  printf '%s\n' 'synthetic signing sentinel' > "$fixture/Signing.$suffix"
  reject_fixture "private signing artifact .$suffix"
  rm "$fixture/Signing.$suffix"
done

python3 - "$fixture/Leak.md" <<'PY_FIXTURE'
from pathlib import Path
import sys
Path(sys.argv[1]).write_text('gh' + 'p_' + 'A' * 30 + '\n')
PY_FIXTURE
reject_fixture 'synthetic credential content'
rm "$fixture/Leak.md"

printf '%s\n' "-----BEGIN ""PRIVATE KEY-----" > "$fixture/Leak.md"
reject_fixture 'synthetic private key marker'
rm "$fixture/Leak.md"
printf '%s\n' "/""Users/example/private" > "$fixture/Leak.md"
reject_fixture 'an absolute local path'
rm "$fixture/Leak.md"
(cd "$fixture" && ./public-artifact-scan.sh)
echo "Publication scanner credential/signing rejection and harmless tooling self-tests passed."
