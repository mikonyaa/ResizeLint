#!/usr/bin/env bash

set -euo pipefail

artifact=${1:-}
profile=${RESIZELINT_NOTARY_PROFILE:-ResizeLintNotary-4NGTWD262W}

if [[ -z "$artifact" || ! -f "$artifact" ]]; then
  echo "Usage: $0 <signed-zip-or-package>" >&2
  exit 2
fi

xcrun notarytool submit "$artifact" \
  --keychain-profile "$profile" \
  --wait

case "$artifact" in
  *.pkg)
    xcrun stapler staple "$artifact"
    xcrun stapler validate "$artifact"
    ;;
esac
