#!/usr/bin/env bash
# Renders every kustomization under kubernetes/ and validates the result against
# the Kubernetes API schemas plus the CRD schemas published by home-operations.
#
# Runs in CI on every pull request, which is what makes `ignoreTests: false` in
# .renovaterc.json5 mean something. Runnable locally the same way:
#
#   ./scripts/validate-kubernetes.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# Validate against the version the cluster actually runs, not the newest schema
# set, otherwise CI would happily accept an API the cluster does not serve yet.
KUBERNETES_VERSION="${KUBERNETES_VERSION:-$(
  sed -nE 's/.*kubernetes_version[[:space:]]*=[[:space:]]*"v?([0-9.]+)".*/\1/p' \
    terraform/envs/production/main.tf | head -1
)}"

if [[ -z "${KUBERNETES_VERSION}" ]]; then
  echo "Could not read kubernetes_version from terraform/envs/production/main.tf" >&2
  exit 1
fi

RENDER_DIR="$(mktemp -d)"
trap 'rm -rf "${RENDER_DIR}"' EXIT

echo "Rendering kustomizations"
render_failed=0
while read -r dir; do
  if ! kustomize build "${dir}" >"${RENDER_DIR}/${dir//\//_}.yaml" 2>"${RENDER_DIR}/stderr"; then
    echo "kustomize build failed: ${dir}" >&2
    sed 's/^/  /' "${RENDER_DIR}/stderr" >&2
    render_failed=1
  fi
done < <(find kubernetes -name kustomization.yaml -printf '%h\n' | sort -u)

rm -f "${RENDER_DIR}/stderr"

if ((render_failed)); then
  exit 1
fi

echo "Validating against Kubernetes ${KUBERNETES_VERSION}"
# -ignore-missing-schemas keeps a brand new CRD from breaking CI before its
# schema is published upstream; those resources are reported as skipped.
kubeconform \
  -kubernetes-version "${KUBERNETES_VERSION}" \
  -schema-location default \
  -schema-location 'https://kubernetes-schemas.pages.dev/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  -ignore-missing-schemas \
  -summary \
  -n 4 \
  "${RENDER_DIR}"
