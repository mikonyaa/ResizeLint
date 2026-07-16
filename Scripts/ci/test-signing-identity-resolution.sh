#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/resizelint-signing-resolution-test.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT

fake_bin="$temporary_root/bin"
mkdir -p "$fake_bin"

cat > "$fake_bin/security" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

case "${1:-}" in
  find-identity)
    printf '  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Developer ID Application: Example (%s)"\n' \
      "${FAKE_APPLICATION_TEAM_ID:-$FAKE_TEAM_ID}"
    awk 'BEGIN { for (i = 0; i < 20000; i++) print "identity detail " i }'
    ;;
  find-certificate)
    for argument in "$@"; do
      case "$argument" in
        -p)
          printf '%s\n' \
            '-----BEGIN CERTIFICATE-----' \
            'ZmFrZQ==' \
            '-----END CERTIFICATE-----'
          exit 0
          ;;
        -Z)
          printf '%s\n' \
            'SHA-256 hash: BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB' \
            'SHA-1 hash: CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC'
          awk 'BEGIN { for (i = 0; i < 20000; i++) print "certificate detail " i }'
          exit 0
          ;;
      esac
    done
    exit 64
    ;;
  *)
    exit 65
    ;;
esac
EOF
chmod 0755 "$fake_bin/security"

cat > "$fake_bin/openssl" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail
cat >/dev/null
printf 'subject=CN = Developer ID Installer: Example (%s), OU = %s\n' "$FAKE_TEAM_ID" "$FAKE_TEAM_ID"
EOF
chmod 0755 "$fake_bin/openssl"

resolver="$repository_root/Scripts/release/resolve-signing-identities.sh"
team_id=9K594G5QQ8
output=$(FAKE_TEAM_ID="$team_id" PATH="$fake_bin:$PATH" "$resolver" test.keychain "$team_id")

test "$(printf '%s\n' "$output" | sed -n '1p')" = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
test "$(printf '%s\n' "$output" | sed -n '2p')" = "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC"
test "$(printf '%s\n' "$output" | sed -n '3p')" = ""

if FAKE_TEAM_ID="$team_id" FAKE_APPLICATION_TEAM_ID=WRONGTEAM PATH="$fake_bin:$PATH" \
  "$resolver" test.keychain WRONGTEAM >"$temporary_root/wrong-team.out" 2>"$temporary_root/wrong-team.err"; then
  echo "Resolver accepted an installer certificate from the wrong team" >&2
  exit 1
fi
grep -q "does not belong to team WRONGTEAM" "$temporary_root/wrong-team.err"

echo "Signing identity resolution test passed."
