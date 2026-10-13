#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
archive=${1:?Usage: test-linux-release-consumer.sh archive version}
version=${2:?Version is required}
archive=$(cd "$(dirname "$archive")" && pwd -P)/$(basename "$archive")
asset="ResizeLint-$version-linux-x86_64.tar.gz"
temporary=$(mktemp -d "${TMPDIR:-/tmp}/resizelint-linux-consumer.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
results=${3:-"$temporary/results"}
mkdir -p "$results"
results=$(cd "$results" && pwd -P)
mkdir -p "$temporary/release"
cp "$archive" "$temporary/release/$asset"
(cd "$temporary/release" && shasum -a 256 "$asset" > SHA256SUMS)

# Only network transport is mocked. The archive, checksum verification, extraction,
# ELF executable, analyzer and Action runner are real in a Swift-free consumer.
cat > "$temporary/curl" <<'CURL_TRANSPORT'
#!/bin/sh
set -eu
output=""
url=""
while [ "$#" -gt 0 ]; do
    case "$1" in --output) shift; output=$1 ;; https://*) url=$1 ;; esac
    shift
done
case "$url" in
    "https://github.com/mikonyaa/ResizeLint/releases/download/$INPUT_VERSION/$RESIZELINT_ASSET") file=$RESIZELINT_ASSET ;;
    "https://github.com/mikonyaa/ResizeLint/releases/download/$INPUT_VERSION/SHA256SUMS") file=SHA256SUMS ;;
    *) echo "Unexpected download URL" >&2; exit 3 ;;
esac
cp "/release/$file" "$output"
CURL_TRANSPORT
chmod +x "$temporary/curl"

for image in ubuntu:22.04 ubuntu:24.04; do
  image_results="$results/${image//[:.]/-}"
  mkdir -p "$image_results"
  docker run --rm --platform linux/amd64 --network none \
    --user "$(id -u):$(id -g)" \
    --label io.github.mikonyaa.resizelint.consumer=release-candidate \
    --volume "$temporary/release:/release:ro" --volume "$temporary/curl:/transport/curl:ro" \
    --volume "$root:/source:ro" --volume "$image_results:/results" \
    --env INPUT_VERSION="$version" --env RESIZELINT_ASSET="$asset" \
    "$image" sh -c '
      set -eu
      test -z "${LD_LIBRARY_PATH:-}"
      ! command -v swift
      cat /etc/os-release
      cat /etc/os-release > /results/os-release
      uname -a > /results/uname.txt
      for file in cpu.max memory.max; do
        test ! -f "/sys/fs/cgroup/$file" || cat "/sys/fs/cgroup/$file" > "/results/$file"
      done
      mkdir -p /tmp/extracted /tmp/positive /tmp/negative
      (cd /release && sha256sum -c SHA256SUMS)
      tar -xzf "/release/$RESIZELINT_ASSET" -C /tmp/extracted
      test "$(/tmp/extracted/resizelint version)" = "$INPUT_VERSION"
      /tmp/extracted/resizelint rules | grep RL009
      printf "%s\n" "let bounds = UIScreen.main.bounds" > /tmp/positive/Canvas.swift
      printf "%s\n" "let width = 100" > /tmp/negative/Canvas.swift
      set +e
      (cd /tmp/positive && /tmp/extracted/resizelint lint . --format json) > /tmp/positive.json
      status=$?
      set -e
      test "$status" = 1
      grep RL001 /tmp/positive.json
      cp /tmp/positive.json /results/positive.json
      (cd /tmp/negative && /tmp/extracted/resizelint lint . --format json) > /tmp/negative.json
      grep -q "\"diagnostics\" : \[" /tmp/negative.json
      cp /tmp/negative.json /results/negative.json
      # Exercise the download/checksum/extraction Action path with the exact archive.
      export PATH="/transport:$PATH" INPUT_PATH=. INPUT_FAIL_ON=error GITHUB_OUTPUT=/tmp/action-output
      export GITHUB_WORKSPACE=/tmp/positive
      set +e
      /source/Scripts/action/run.sh
      status=$?
      set -e
      test "$status" = 1
      grep -q RL001 /tmp/positive/.resizelint-results.sarif
      grep -q utf16CodeUnits /tmp/positive/.resizelint-results.sarif
      cp /tmp/positive/.resizelint-results.sarif /results/positive.sarif
      export GITHUB_WORKSPACE=/tmp/negative
      /source/Scripts/action/run.sh
      ! grep -q ruleId /tmp/negative/.resizelint-results.sarif
      cp /tmp/negative/.resizelint-results.sarif /results/negative.sarif
      export INPUT_CONFIG=missing.yml
      : > "$GITHUB_OUTPUT"
      set +e
      /source/Scripts/action/run.sh
      status=$?
      set -e
      test "$status" = 2
      test ! -f /tmp/negative/.resizelint-results.sarif
      test ! -s "$GITHUB_OUTPUT"
      echo "Swift-free archive and real Action consumer passed (download transport mocked)."
    '
  docker image inspect "$image" --format '{{json .RepoDigests}}' > "$image_results/image-digests.json"
  python3 - "$root" "$image_results" <<'PYTHON_VALIDATION'
import json, pathlib, sys
import jsonschema
root, results = map(pathlib.Path, sys.argv[1:])
positive = json.loads((results / "positive.json").read_text())
negative = json.loads((results / "negative.json").read_text())
assert any(d["ruleID"] == "RL001" for d in positive["diagnostics"])
assert negative["diagnostics"] == []
json_schema = json.loads((root / "Schemas/resizelint-report-v1.schema.json").read_text())
for report in (positive, negative):
    jsonschema.Draft202012Validator(json_schema).validate(report)
schema = json.loads((root / "Schemas/sarif-2.1.0.schema.json").read_text())
for name in ("positive", "negative"):
    sarif = json.loads((results / f"{name}.sarif").read_text())
    jsonschema.Draft7Validator(schema).validate(sarif)
    assert sarif["runs"][0]["columnKind"] == "utf16CodeUnits"
    assert bool(sarif["runs"][0]["results"]) == (name == "positive")
print("Real archive JSON and Action SARIF fully validated.")
PYTHON_VALIDATION
done

mkdir -p "$temporary/corrupt"
cp "$temporary/release/"* "$temporary/corrupt/"
printf 'synthetic corruption' >> "$temporary/corrupt/$asset"
docker run --rm --platform linux/amd64 --network none \
  --label io.github.mikonyaa.resizelint.consumer=release-candidate \
  --volume "$temporary/corrupt:/release:ro" --volume "$temporary/curl:/transport/curl:ro" \
  --volume "$root:/source:ro" --env INPUT_VERSION="$version" --env RESIZELINT_ASSET="$asset" \
  ubuntu:22.04 sh -c '
    mkdir -p /tmp/workspace
    export PATH="/transport:$PATH" GITHUB_WORKSPACE=/tmp/workspace INPUT_PATH=. GITHUB_OUTPUT=/tmp/output
    /source/Scripts/action/run.sh
    status=$?
    test "$status" = 3 && test ! -s /tmp/output && test ! -f /tmp/workspace/.resizelint-results.sarif
  '
echo "Action rejects a corrupted archive before execution."
