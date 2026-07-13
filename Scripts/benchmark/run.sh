#!/usr/bin/env bash

set -euo pipefail

binary=${1:-}
line_count=${2:-250000}
maximum_seconds=${3:-10}
script_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

if [[ -z "$binary" || ! -x "$binary" ]]; then
  echo "usage: $0 <resizelint-binary> [line-count] [maximum-seconds]" >&2
  exit 2
fi
binary=$(cd "$(dirname "$binary")" && pwd -P)/$(basename "$binary")

fixture=$(mktemp -d "${TMPDIR:-/tmp}/resizelint-benchmark.XXXXXX")
cleanup() {
  rm -rf "$fixture"
}
trap cleanup EXIT

"$script_directory/generate-fixture.sh" "$fixture" "$line_count"

for run in 1 2 3; do
  (
    cd "$fixture"
    /usr/bin/time -p "$binary" lint . \
      --format sarif \
      --output "run${run}.sarif" \
      --no-color \
      --jobs 8
  ) 2> "$fixture/run${run}.time"
done

hashes=$(shasum -a 256 "$fixture"/run*.sarif | awk '{ print $1 }' | sort -u)
if [[ "$(printf '%s\n' "$hashes" | wc -l | tr -d ' ')" != "1" ]]; then
  echo "benchmark reports were not deterministic" >&2
  exit 1
fi

maximum_observed=$(awk '$1 == "real" { if ($2 > max) max = $2 } END { print max + 0 }' "$fixture"/run*.time)
if ! awk -v observed="$maximum_observed" -v limit="$maximum_seconds" 'BEGIN { exit !(observed <= limit) }'; then
  echo "benchmark exceeded ${maximum_seconds}s: ${maximum_observed}s" >&2
  exit 1
fi

echo "maximum real time: ${maximum_observed}s"
echo "deterministic SARIF SHA-256: $hashes"
