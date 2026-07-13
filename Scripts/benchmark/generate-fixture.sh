#!/usr/bin/env bash

set -euo pipefail

destination=${1:-}
line_count=${2:-250000}
lines_per_file=${LINES_PER_FILE:-1000}

if [[ -z "$destination" || "$destination" == "/" ]]; then
  echo "usage: $0 <empty-destination> [line-count]" >&2
  exit 2
fi

if ! [[ "$line_count" =~ ^[1-9][0-9]*$ && "$lines_per_file" =~ ^[1-9][0-9]*$ ]]; then
  echo "line counts must be positive integers" >&2
  exit 2
fi

mkdir -p "$destination"
if [[ -n "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  echo "destination must be empty: $destination" >&2
  exit 2
fi

generated=0
file_index=0
while (( generated < line_count )); do
  remaining=$((line_count - generated))
  count=$lines_per_file
  if (( remaining < count )); then
    count=$remaining
  fi
  file=$(printf '%s/Fixture%04d.swift' "$destination" "$file_index")
  awk -v start="$generated" -v count="$count" 'BEGIN {
    for (i = 0; i < count; i++) {
      printf("let fixtureValue%09d = %d\n", start + i, start + i)
    }
  }' > "$file"
  generated=$((generated + count))
  file_index=$((file_index + 1))
done

actual=$(find "$destination" -type f -name '*.swift' -print0 | xargs -0 wc -l | awk 'END { print $1 }')
if [[ "$actual" != "$line_count" ]]; then
  echo "fixture generation failed: expected $line_count lines, found $actual" >&2
  exit 3
fi

echo "$actual Swift lines in $file_index files"
