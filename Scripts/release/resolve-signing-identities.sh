#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 <keychain> <team-id>" >&2
  exit 64
fi

keychain=$1
team_id=$2

application_listing=$(security find-identity -v -p codesigning "$keychain")
application_identity=$(awk -v team="$team_id" '
  identity == "" && index($0, "Developer ID Application:") && index($0, "(" team ")") {
    identity = $2
  }
  END {
    if (identity != "") print identity
  }
' <<<"$application_listing")

if [[ -z "$application_identity" ]]; then
  echo "Developer ID Application identity for team $team_id was not found" >&2
  exit 1
fi

installer_pem=$(security find-certificate -a -c "Developer ID Installer" -p "$keychain")
installer_subject=$(openssl x509 -inform pem -noout -subject <<<"$installer_pem")
if [[ "$installer_subject" != *"$team_id"* ]]; then
  echo "Developer ID Installer certificate does not belong to team $team_id" >&2
  exit 1
fi

installer_listing=$(security find-certificate -a -c "Developer ID Installer" -Z "$keychain")
installer_identity=$(awk '
  identity == "" && /SHA-1 hash:/ {
    identity = $3
  }
  END {
    if (identity != "") print identity
  }
' <<<"$installer_listing")

if [[ -z "$installer_identity" ]]; then
  echo "Developer ID Installer identity was not found" >&2
  exit 1
fi

printf '%s\n%s\n' "$application_identity" "$installer_identity"
