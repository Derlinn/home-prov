#!/usr/bin/env bash
# Fails if any *.sops.yaml tracked in git is not actually encrypted.
#
# A file named *.sops.yaml that never went through `sops --encrypt` looks
# perfectly ordinary in a diff, which is how an unencrypted one already reached
# main once. Nothing else in the repo checks this.
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

status=0
while read -r file; do
  [[ -f "${file}" ]] || continue
  # The repo-root .sops.yaml is the SOPS config, not a secret.
  [[ "${file}" == ".sops.yaml" || "${file}" == ".sops.yml" ]] && continue
  if ! grep -q 'ENC\[AES256_GCM' "${file}"; then
    echo "not encrypted: ${file}" >&2
    status=1
  fi
done < <(git ls-files '*.sops.yaml' '*.sops.yml')

if ((status)); then
  echo >&2
  echo "Encrypt each file above with: sops --encrypt --in-place <file>" >&2
  exit 1
fi

echo "All SOPS files are encrypted"
