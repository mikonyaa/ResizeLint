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
    output_mode=default
    for argument in "$@"; do
      case "$argument" in
        -p)
          output_mode=pem
          ;;
        -Z)
          output_mode=hash
          ;;
      esac
    done
    if [[ "$output_mode" == hash ]]; then
      printf '%s\n' \
        'SHA-256 hash: BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB' \
        'SHA-1 hash: CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC'
      awk 'BEGIN { for (i = 0; i < 20000; i++) print "certificate detail " i }'
    else
      printf '%s\n' \
        '-----BEGIN CERTIFICATE-----' \
        'ZmFrZQ==' \
        '-----END CERTIFICATE-----'
    fi
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

cat > "$fake_bin/xcrun" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail
[[ "${1:-}" == notarytool && "${2:-}" == --help ]]
EOF
chmod 0755 "$fake_bin/xcrun"

resolver="$repository_root/Scripts/release/resolve-signing-identities.sh"
team_id=4NGTWD262W
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

distribution_team_id=4NGTWD262W
if ! readiness_output=$(
  FAKE_TEAM_ID="$distribution_team_id" PATH="$fake_bin:$PATH" \
    "$repository_root/Scripts/release/verify-signing-readiness.sh"
); then
  echo "Signing readiness rejected distribution team $distribution_team_id" >&2
  exit 1
fi
grep -q "Developer ID Application ($distribution_team_id): ready" <<<"$readiness_output"
grep -q "Developer ID Installer ($distribution_team_id): ready" <<<"$readiness_output"
grep -q "notarytool: available" <<<"$readiness_output"

echo "Signing identity resolution test passed."
