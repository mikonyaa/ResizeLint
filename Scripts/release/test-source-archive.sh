#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
builder="$repository_root/Scripts/release/build-source-archive.sh"

if [[ ! -x "$builder" ]]; then
  echo "Source archive builder is missing or not executable: $builder" >&2
  exit 1
fi

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/resizelint-source-test.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT

first=$($builder "$temporary_root/first" 1.0.0)
second=$($builder "$temporary_root/second" 1.0.0)
first_hash=$(shasum -a 256 "$first" | awk '{ print $1 }')
second_hash=$(shasum -a 256 "$second" | awk '{ print $1 }')

if [[ "$first_hash" != "$second_hash" ]]; then
  echo "Source archives are not reproducible" >&2
  exit 1
fi

listing="$temporary_root/listing.txt"
tar -tzf "$first" > "$listing"
grep -q '^ResizeLint-1.0.0/Package.swift$' "$listing"

if grep -Eq '(^|/)Formula/|(^|/)\.build/|(^|/)\.git/' "$listing"; then
  echo "Source archive contains a release-excluded path" >&2
  exit 1
fi

echo "Source archive self-test passed: $first_hash"
