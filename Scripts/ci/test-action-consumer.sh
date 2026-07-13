#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
runner="$repository_root/Scripts/action/run.sh"
binary=${1:-"$repository_root/.build/release/resizelint"}

if [ ! -x "$runner" ]; then
    echo "Action runner is missing or not executable: $runner" >&2
    exit 1
fi

if [ ! -x "$binary" ]; then
    echo "ResizeLint release binary is missing or not executable: $binary" >&2
    exit 1
fi

temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/resizelint-action-consumer.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT HUP INT TERM

run_fixture() {
    fixture_name=$1
    expected_status=$2
    expected_rule=$3
    workspace="$temporary_root/$fixture_name"
    mkdir -p "$workspace"
    cp -R "$repository_root/Tests/Fixtures/ActionConsumer/$fixture_name/." "$workspace/"

    output_file="$temporary_root/$fixture_name.output"
    : > "$output_file"

    set +e
    GITHUB_WORKSPACE="$workspace" \
    GITHUB_OUTPUT="$output_file" \
    INPUT_PATH="." \
    INPUT_CONFIG="" \
    INPUT_FAIL_ON="error" \
    INPUT_VERSION="1.0.0" \
        "$runner" "$binary"
    status=$?
    set -e

    if [ "$status" -ne "$expected_status" ]; then
        echo "$fixture_name returned $status; expected $expected_status" >&2
        exit 1
    fi

    sarif_path=$(sed -n 's/^sarif=//p' "$output_file")
    if [ -z "$sarif_path" ] || [ ! -f "$sarif_path" ]; then
        echo "$fixture_name did not expose an existing SARIF file" >&2
        exit 1
    fi

    if [ -n "$expected_rule" ]; then
        if ! grep -q "\"ruleId\"[[:space:]]*:[[:space:]]*\"$expected_rule\"" "$sarif_path"; then
            echo "$fixture_name SARIF does not contain $expected_rule" >&2
            exit 1
        fi
    elif grep -q '"ruleId"' "$sarif_path"; then
        echo "$fixture_name SARIF unexpectedly contains a diagnostic" >&2
        exit 1
    fi
}

run_fixture Legacy 1 RL001
run_fixture Adaptive 0 ""

echo "GitHub Action consumer fixtures passed."
