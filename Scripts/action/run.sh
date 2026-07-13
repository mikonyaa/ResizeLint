#!/bin/sh

set -eu

if [ "$#" -gt 1 ]; then
    echo "Usage: run.sh [local-resizelint-binary]" >&2
    exit 2
fi

workspace=${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is required}
input_path=${INPUT_PATH:-.}
input_config=${INPUT_CONFIG:-}
fail_on=${INPUT_FAIL_ON:-error}
version=${INPUT_VERSION:-1.0.0}

case "$fail_on" in
    error|warning|info) ;;
    *)
        echo "Unsupported fail-on value: $fail_on" >&2
        exit 2
        ;;
esac

case "$version" in
    *[!0-9A-Za-z.-]*|.*|*..*|*/*|"")
        echo "Unsupported ResizeLint version: $version" >&2
        exit 2
        ;;
esac

if [ ! -d "$workspace" ]; then
    echo "GITHUB_WORKSPACE does not exist: $workspace" >&2
    exit 2
fi

temporary_root=""
cleanup() {
    if [ -n "$temporary_root" ]; then
        rm -rf "$temporary_root"
    fi
}
trap cleanup EXIT HUP INT TERM

if [ "$#" -eq 1 ]; then
    binary_directory=$(CDPATH= cd -- "$(dirname -- "$1")" && pwd -P)
    binary="$binary_directory/$(basename -- "$1")"
    if [ ! -x "$binary" ]; then
        echo "Local ResizeLint binary is not executable: $binary" >&2
        exit 2
    fi
else
    temporary_root=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/resizelint-action.XXXXXX")
    operating_system=$(uname -s)
    architecture=$(uname -m)

    case "$operating_system:$architecture" in
        Darwin:arm64|Darwin:x86_64)
            asset="ResizeLint-$version-macos-universal.zip"
            archive_kind=zip
            ;;
        Linux:x86_64|Linux:amd64)
            asset="ResizeLint-$version-linux-x86_64.tar.gz"
            archive_kind=tar
            ;;
        *)
            echo "Unsupported runner: $operating_system $architecture" >&2
            exit 2
            ;;
    esac

    release_url="https://github.com/mikonyaa/ResizeLint/releases/download/$version"
    archive="$temporary_root/$asset"
    checksums="$temporary_root/SHA256SUMS"

    curl --fail --location --proto '=https' --tlsv1.2 --retry 3 \
        --output "$archive" "$release_url/$asset"
    curl --fail --location --proto '=https' --tlsv1.2 --retry 3 \
        --output "$checksums" "$release_url/SHA256SUMS"

    expected=$(awk -v asset="$asset" '$2 == asset || $2 == "*" asset { print $1; exit }' "$checksums")
    if [ -z "$expected" ]; then
        echo "SHA256SUMS does not contain $asset" >&2
        exit 3
    fi

    case "$operating_system" in
        Darwin) actual=$(shasum -a 256 "$archive" | awk '{ print $1 }') ;;
        Linux) actual=$(sha256sum "$archive" | awk '{ print $1 }') ;;
    esac

    if [ "$actual" != "$expected" ]; then
        echo "SHA-256 verification failed for $asset" >&2
        exit 3
    fi

    case "$archive_kind" in
        zip) unzip -q "$archive" -d "$temporary_root/extracted" ;;
        tar)
            mkdir -p "$temporary_root/extracted"
            tar -xzf "$archive" -C "$temporary_root/extracted"
            ;;
    esac

    binary="$temporary_root/extracted/resizelint"
    if [ ! -f "$binary" ]; then
        echo "Release asset does not contain resizelint at its root" >&2
        exit 3
    fi
    chmod +x "$binary"
fi

report="$workspace/.resizelint-results.sarif"
set -- lint "$input_path" --format sarif --output "$report" --fail-on "$fail_on" --no-color
if [ -n "$input_config" ]; then
    set -- "$@" --config "$input_config"
fi

set +e
(cd "$workspace" && "$binary" "$@")
status=$?
set -e

if [ ! -f "$report" ]; then
    echo "ResizeLint did not produce the expected SARIF report" >&2
    exit 3
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf 'sarif=%s\n' "$report" >> "$GITHUB_OUTPUT"
else
    printf 'sarif=%s\n' "$report"
fi

exit "$status"
