#!/usr/bin/env bash

set -euo pipefail

team_id=4NGTWD262W
application_ready=0
installer_ready=0
tool_ready=0

application_listing=$(security find-identity -v -p codesigning 2>/dev/null || true)
if grep -E -q "Developer ID Application:.*\\($team_id\\)" <<<"$application_listing"; then
  application_ready=1
fi

installer_pem=$(security find-certificate -a -c "Developer ID Installer" -p 2>/dev/null || true)
installer_subject=$(openssl x509 -inform pem -noout -subject <<<"$installer_pem" 2>/dev/null || true)
if [[ "$installer_subject" == *"$team_id"* ]]; then
  installer_ready=1
fi

if xcrun notarytool --help >/dev/null 2>&1; then
  tool_ready=1
fi

printf 'Developer ID Application (%s): %s\n' "$team_id" "$([[ $application_ready -eq 1 ]] && echo ready || echo missing)"
printf 'Developer ID Installer (%s): %s\n' "$team_id" "$([[ $installer_ready -eq 1 ]] && echo ready || echo missing)"
printf 'notarytool: %s\n' "$([[ $tool_ready -eq 1 ]] && echo available || echo missing)"

if [[ $application_ready -ne 1 || $installer_ready -ne 1 || $tool_ready -ne 1 ]]; then
  exit 1
fi
