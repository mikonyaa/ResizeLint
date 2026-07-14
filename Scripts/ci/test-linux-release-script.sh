#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/resizelint-linux-release-test.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT

fake_bin="$temporary_root/bin"
destination="$temporary_root/artifacts"
mkdir -p "$fake_bin"

cat > "$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

expected_user="$(id -u):$(id -g)"
container_user=""
build_root=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --user)
      shift
      container_user=${1:-}
      ;;
    --volume)
      shift
      case "${1:-}" in
        *:/build)
          build_root=${1%:/build}
          ;;
      esac
      ;;
  esac
  shift
done

if [[ "$container_user" != "$expected_user" ]]; then
  echo "Docker build must run as host user $expected_user; received ${container_user:-root/default}" >&2
  exit 64
fi

if [[ -z "$build_root" ]]; then
  echo "Docker build volume was not provided" >&2
  exit 65
fi

binary="$build_root/x86_64-unknown-linux-gnu/release/resizelint"
mkdir -p "$(dirname "$binary")"
printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "1.0.0"' > "$binary"
chmod 0755 "$binary"
EOF
chmod 0755 "$fake_bin/docker"

PATH="$fake_bin:$PATH" \
  "$repository_root/Scripts/release/build-linux.sh" "$destination" 1.0.0 >/dev/null

archive="$destination/ResizeLint-1.0.0-linux-x86_64.tar.gz"
test -f "$archive"
test "$(tar -tzf "$archive")" = "resizelint"

mkdir -p "$temporary_root/extracted"
tar -xzf "$archive" -C "$temporary_root/extracted"
test "$("$temporary_root/extracted/resizelint")" = "1.0.0"

echo "Linux release script ownership and archive test passed."
