#!/usr/bin/env bash

set -euo pipefail

repository_root=$(git rev-parse --show-toplevel)
cd "$repository_root"

forbidden_terms=(
  "co""dex"
  "open""ai"
  "chat""gpt"
  "clau""de"
  "co""pilot"
  "pro""mpt"
  "agent"" plan"
  "AI""-generated"
  ".co""dex"
  "AGENTS"".md"
  "pasted""-text"
)

forbidden_paths=(
  ".co""dex"
  "AGENTS"".md"
  "pasted""-text"
  "implementation""-plan"
  ".p12"
  ".p8"
  ".mobileprovision"
  "provisioning""profile"
  "derived""data"
)

sensitive_markers=(
  "/""Users/"
  "@""icloud.com"
  "BEGIN ""PRIVATE KEY"
  "BEGIN ""ENCRYPTED PRIVATE KEY"
)

files=()
while IFS= read -r -d '' file; do
  files+=("$file")
done < <(git ls-files -z --cached --others --exclude-standard)

failed=0
for file in "${files[@]}"; do
  lowercase_path=$(printf '%s' "$file" | tr '[:upper:]' '[:lower:]')
  for forbidden_path in "${forbidden_paths[@]}"; do
    lowercase_forbidden=$(printf '%s' "$forbidden_path" | tr '[:upper:]' '[:lower:]')
    if [[ "$lowercase_path" == *"$lowercase_forbidden"* ]]; then
      echo "Rejected public path: $file" >&2
      failed=1
    fi
  done

  [[ -f "$file" ]] || continue
  for term in "${forbidden_terms[@]}"; do
    if LC_ALL=C grep -I -i -F -q -- "$term" "$file"; then
      echo "Rejected internal marker in: $file" >&2
      failed=1
    fi
  done
  for marker in "${sensitive_markers[@]}"; do
    if LC_ALL=C grep -I -F -q -- "$marker" "$file"; then
      echo "Rejected sensitive marker in: $file" >&2
      failed=1
    fi
  done
  if LC_ALL=C grep -I -E -q -- '(gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----)' "$file"; then
    echo "Rejected credential-shaped content in: $file" >&2
    failed=1
  fi
done

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "Publication hygiene scan passed for ${#files[@]} candidate files."
