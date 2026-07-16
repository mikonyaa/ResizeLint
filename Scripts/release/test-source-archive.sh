#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
builder="$repository_root/Scripts/release/build-source-archive.sh"
formula="$repository_root/Formula/resizelint.rb"

if [[ ! -x "$builder" ]]; then
  echo "Source archive builder is missing or not executable: $builder" >&2
  exit 1
fi

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/resizelint-source-test.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT

fake_bin="$temporary_root/bin"
mkdir -p "$fake_bin"
real_tar=$(command -v tar)
cat > "$fake_bin/tar" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail
echo "Source archive builder must not invoke system tar" >&2
exit 66
EOF
chmod 0755 "$fake_bin/tar"

first=$(PATH="$fake_bin:$PATH" "$builder" "$temporary_root/first" 1.0.0)
second=$(PATH="$fake_bin:$PATH" "$builder" "$temporary_root/second" 1.0.0)
first_hash=$(shasum -a 256 "$first" | awk '{ print $1 }')
second_hash=$(shasum -a 256 "$second" | awk '{ print $1 }')

if [[ "$first_hash" != "$second_hash" ]]; then
  echo "Source archives are not reproducible" >&2
  exit 1
fi

if [[ "${RESIZELINT_VERIFY_FORMULA_CHECKSUM:-0}" == "1" ]]; then
  formula_hash=$(awk '/^[[:space:]]*sha256 / { gsub(/"/, "", $2); print $2; exit }' "$formula")
  if [[ -z "$formula_hash" ]]; then
    echo "Homebrew formula does not declare a source archive checksum" >&2
    exit 1
  fi
  if [[ "$formula_hash" != "$first_hash" ]]; then
    echo "Homebrew formula checksum is $formula_hash; source archive checksum is $first_hash" >&2
    exit 1
  fi
fi

listing="$temporary_root/listing.txt"
"$real_tar" -tzf "$first" > "$listing"
grep -q '^ResizeLint-1.0.0/Package.swift$' "$listing"
grep -q '^ResizeLint-1.0.0/Tests/ResizeLintCoreTests/VersionTests.swift$' "$listing"

if grep -Eq '(^|/)Formula/|(^|/)\.build/|(^|/)\.git/' "$listing"; then
  echo "Source archive contains a release-excluded path" >&2
  exit 1
fi

echo "Source archive reproducibility test passed: $first_hash"
if [[ "${RESIZELINT_VERIFY_FORMULA_CHECKSUM:-0}" == "1" ]]; then
  echo "Homebrew formula checksum test passed."
fi
