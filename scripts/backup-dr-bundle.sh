#!/usr/bin/env bash
# Bundles the material that cannot be regenerated, and encrypts it under a
# passphrase.
#
# Two things in this setup exist in exactly one copy, on this host's disk only:
#
#   - the SOPS age key. Lose it and every *.sops.yaml in the repo is
#     permanently unreadable. The repo is public, so the ciphertext is already
#     mirrored worldwide -- the key is the only thing standing between that
#     ciphertext and everyone.
#   - the Talos PKI (talosconfig + machine configs). Lose it and there is no
#     admin access to the cluster again. These normally live in the Terraform
#     state, which no longer exists here.
#
# The bundle is encrypted with a passphrase rather than with the age key,
# because a bundle that contains the age key cannot be encrypted to that same
# key. The passphrase must therefore be stored somewhere that does not depend
# on this machine or on the cluster -- in particular NOT in the Vaultwarden
# instance running in that cluster.
#
# Usage: scripts/backup-dr-bundle.sh [destination-dir]

set -euo pipefail
umask 077

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

env_name="${NODE_ENV:-production}"
dest_dir="${1:-/mnt/nas-home/home-prov-dr}"
output_dir="terraform/envs/${env_name}/output"

age_key="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
age_key="${age_key/#\~/$HOME}"

for tool in age age-keygen tar sha256sum; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "error: $tool not found. Run 'mise install'." >&2
        exit 1
    fi
done

# Collect the sources, refusing to produce a bundle that silently omits one of
# them -- a partial DR bundle is worse than none, because it looks like a
# backup.
sources=("$age_key" ".sops.yaml" "$output_dir/talos-config.yaml")
while IFS= read -r -d '' f; do
    sources+=("$f")
done < <(find "$output_dir" -maxdepth 1 -name 'talos-machine-config-*.yaml' -print0 2>/dev/null | sort -z)

missing=0
for f in "${sources[@]}"; do
    [[ -f $f ]] || { echo "error: missing $f" >&2; missing=1; }
done
[[ $missing -eq 0 ]] || exit 1

if [[ ${#sources[@]} -lt 4 ]]; then
    echo "error: no Talos machine config found in $output_dir" >&2
    exit 1
fi

# Guard against backing up the wrong age key: derive its public key and compare
# it with the recipient the repo actually encrypts to.
recipient=$(grep -oE 'age1[a-z0-9]{20,}' .sops.yaml | head -1)
derived=$(age-keygen -y "$age_key" 2>/dev/null | head -1)
if [[ -n $recipient && $derived != "$recipient" ]]; then
    echo "error: $age_key does not match the recipient in .sops.yaml." >&2
    echo "       Backing it up would produce a bundle that cannot decrypt the repo." >&2
    exit 1
fi

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
bundle="$stage/bundle"
mkdir -p "$bundle"

for f in "${sources[@]}"; do
    cp -- "$f" "$bundle/$(basename "$f")"
done

{
    echo "home-prov disaster recovery bundle"
    echo "created:     $(date -Is)"
    echo "host:        $(hostname)"
    echo "environment: $env_name"
    echo "git commit:  $(git rev-parse HEAD 2>/dev/null || echo 'n/a')"
    echo "age recipient: ${recipient:-unknown}"
    echo
    echo "contents (sha256):"
    (cd "$bundle" && sha256sum -- * | sed 's/^/  /')
    echo
    echo "restore:"
    echo "  age -d -o bundle.tar.gz <this-file> && tar xzf bundle.tar.gz"
    echo "  install -m600 -D bundle/keys.txt ~/.config/sops/age/keys.txt"
    echo "  install -m600 -D bundle/talos-config.yaml \\"
    echo "    <repo>/terraform/envs/$env_name/output/talos-config.yaml"
    echo
    echo "  The machine configs rebuild a node with the same PKI:"
    echo "    talosctl apply-config --insecure --nodes <ip> \\"
    echo "      --file bundle/talos-machine-config-<node>.yaml"
} > "$bundle/MANIFEST.txt"

mkdir -p "$dest_dir"

# An unmounted NAS leaves an empty mount point behind, and mkdir -p then creates
# the destination on the root filesystem instead -- the very disk this bundle
# exists to survive, with every step still reporting success. Sharing a device
# with / means the mount is not there.
if [[ -z ${ALLOW_LOCAL_DEST:-} && $(stat -c %d "$dest_dir") == "$(stat -c %d /)" ]]; then
    echo "error: $dest_dir is on the root filesystem, so the NAS is not mounted." >&2
    echo "       Mount it, or set ALLOW_LOCAL_DEST=1 to write locally on purpose." >&2
    exit 1
fi

stamp=$(date +%Y%m%dT%H%M%S)
target="$dest_dir/home-prov-dr-$stamp.tar.gz.age"

echo "Bundling $(( ${#sources[@]} )) files. You will be asked for a passphrase twice."
tar czf "$stage/bundle.tar.gz" -C "$stage" bundle
age -p -o "$target" "$stage/bundle.tar.gz"

# A backup that has never been decrypted is a hypothesis. Verify before
# reporting success -- this prompts for the passphrase once more, which also
# confirms it was typed as intended.
echo "Verifying the bundle decrypts. Enter the same passphrase."
if ! age -d -o "$stage/verify.tar.gz" "$target"; then
    rm -f "$target"
    echo "error: the bundle could not be decrypted. It has been removed." >&2
    exit 1
fi

if ! cmp -s "$stage/bundle.tar.gz" "$stage/verify.tar.gz"; then
    rm -f "$target"
    echo "error: the decrypted bundle does not match the source. It has been removed." >&2
    exit 1
fi

chmod 600 "$target" 2>/dev/null || true

# MANIFEST.txt explains how to restore, but it lives inside the encrypted
# bundle -- unreadable until you remember the one step you may have forgotten.
# This companion file stays in clear text next to the bundles and holds nothing
# secret: only how to open one, and which key it should turn out to contain.
bundle_name=$(basename "$target")
cat > "$dest_dir/RESTORE.txt" <<EOF
home-prov disaster recovery -- how to open a bundle

Latest bundle: $bundle_name
sha256:        $(sha256sum "$target" | cut -d' ' -f1)
written:       $(date -Is)

The bundle is an age file encrypted with a PASSPHRASE (age -p, scrypt), not
with the repository age key -- that key is inside the bundle.

  age -d -o bundle.tar.gz $bundle_name
  tar xzf bundle.tar.gz
  cat bundle/MANIFEST.txt    # full restore procedure, checksums, node configs

It should contain the age identity for this recipient:
  ${recipient:-unknown}
Confirm it matches .sops.yaml in the repository before trusting a restore.

The passphrase is deliberately stored nowhere on this NAS, on the workstation
that wrote this file, or in the cluster's Vaultwarden -- all three are assumed
lost in the scenario this bundle exists for. Keep it on paper off-site and in a
password manager that depends on none of them. Without it, nothing here can be
recovered.

This file is intentionally unencrypted. Do not add secrets to it.
EOF
chmod 644 "$dest_dir/RESTORE.txt" 2>/dev/null || true

echo
echo "Written and verified: $target"
sha256sum "$target" | sed 's/^/  /'
echo "Wrote $dest_dir/RESTORE.txt (plain text, no secrets)."
echo
echo "This destination is on the same site as the cluster. Copy the file to"
echo "somewhere else as well, and store the passphrase outside this machine"
echo "and outside the cluster."
