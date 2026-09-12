#!/usr/bin/env bash
# Fails when the pinned Talos and Kubernetes versions form a combination
# SideroLabs does not support. Renovate cannot read that matrix, and merging
# an unsupported pair leaves tuppr's KubernetesUpgrade failing permanently
# (seen 2026-09-12: Talos 1.13 + Kubernetes 1.37).
#
# Runs in CI on every pull request touching versions, which is what makes it
# gate Renovate (`ignoreTests: false` in .renovaterc.json5). Runnable locally:
#
#   ./scripts/check-talos-k8s-matrix.sh [ROOT]
#
# Needs no tools beyond bash, sed and grep.
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Highest Kubernetes minor each Talos minor supports, from
# https://docs.siderolabs.com/talos/<v>/getting-started/support-matrix
# Fail-closed: an unknown Talos minor fails with instructions to extend this.
declare -A MAX_K8S=(
  ["1.12"]="1.35"
  ["1.13"]="1.36"
  ["1.14"]="1.37"
)

tf_version() {
  sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"v?([0-9]+\.[0-9]+\.[0-9]+)\".*/\1/p" "$2" | head -1
}

cr_version() {
  sed -nE 's/^[[:space:]]*version:[[:space:]]*v?([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' "$1" | head -1
}

minor_of() {
  cut -d. -f1,2 <<<"$1"
}

failures=0
fail() {
  echo "  ✗ $1" >&2
  failures=$((failures + 1))
}

TALOS_CR="${ROOT}/kubernetes/apps/system-upgrade/tuppr/upgrades/talosupgrade.yaml"
K8S_CR="${ROOT}/kubernetes/apps/system-upgrade/tuppr/upgrades/kubernetesupgrade.yaml"
talos_cr="$(cr_version "${TALOS_CR}")"
k8s_cr="$(cr_version "${K8S_CR}")"
[[ -n "${talos_cr}" && -n "${k8s_cr}" ]] || {
  echo "Could not read versions from the tuppr upgrade CRs" >&2
  exit 1
}

# The Terraform pins provision new nodes while the tuppr CRs upgrade live
# ones: both must describe the same pair, otherwise one of the two upgrades
# something else.
for env in pre-production production; do
  tf="${ROOT}/terraform/envs/${env}/main.tf"
  talos_tf="$(tf_version talos_version "${tf}")"
  k8s_tf="$(tf_version kubernetes_version "${tf}")"
  [[ -n "${talos_tf}" && -n "${k8s_tf}" ]] || {
    echo "Could not read versions from ${tf}" >&2
    exit 1
  }
  [[ "${talos_tf}" == "${talos_cr}" ]] || fail "${env}: talos_version ${talos_tf} != talosupgrade.yaml ${talos_cr}"
  [[ "${k8s_tf}" == "${k8s_cr}" ]] || fail "${env}: kubernetes_version ${k8s_tf} != kubernetesupgrade.yaml ${k8s_cr}"

  talos_minor="$(minor_of "${talos_tf}")"
  k8s_minor="$(minor_of "${k8s_tf}")"
  max_k8s="${MAX_K8S[${talos_minor}]:-}"
  if [[ -z "${max_k8s}" ]]; then
    fail "${env}: unknown Talos minor ${talos_minor}, extend MAX_K8S in $0 from the SideroLabs support matrix"
    continue
  fi
  if ((10#$(cut -d. -f2 <<<"${k8s_minor}") > 10#$(cut -d. -f2 <<<"${max_k8s}"))); then
    fail "${env}: Kubernetes ${k8s_minor} exceeds the maximum ${max_k8s} supported by Talos ${talos_minor}"
  else
    echo "  ✓ ${env}: Talos ${talos_tf} + Kubernetes ${k8s_tf} (max ${max_k8s})"
  fi
done

if ((failures)); then
  echo "Unsupported Talos/Kubernetes version combination." >&2
  exit 1
fi
