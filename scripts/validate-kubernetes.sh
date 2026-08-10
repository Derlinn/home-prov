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

# Flux replaces ${VAR} from the cluster-settings ConfigMap before applying, so
# validate what the cluster actually receives, not the raw templates. An
# HTTPRoute hostname of "app.${DOMAIN}" fails schema validation on its own.
SETTINGS_FILE="kubernetes/components/cluster-settings/configmap.yaml"
setting_keys=()
while IFS= read -r line; do
  key="${line%%: *}"
  export "${key}=${line#*: }"
  setting_keys+=("${key}")
done < <(sed -nE '/^data:/,/^[^[:space:]]/ s/^  ([A-Za-z_][A-Za-z0-9_]*):[[:space:]]*(.+)$/\1: \2/p' "${SETTINGS_FILE}")

# Variables that legitimately survive substitution: some come from Secrets that
# never land in Git, others are resolved at runtime by the app itself on
# resources annotated kustomize.toolkit.fluxcd.io/substitute: disabled.
EXTERNAL_VARS=(
  CLOUDFLARE_TUNNEL_ID
  PDNS_API_KEY
  GF_AUTH_GENERIC_OAUTH_CLIENT_ID
  GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET
  datasource
  logsource
  namespace
  pod
  PORT
)
for var in "${EXTERNAL_VARS[@]}"; do
  export "${var}="
done

# Undefined variables are replaced with an empty string by Flux, without any
# error. "https://${DOMAIN}" silently becoming "https://" is the failure mode
# this guard exists to prevent.
undefined=()
while read -r var; do
  [[ -v "${var}" ]] || undefined+=("${var}")
done < <(grep -ohE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "${RENDER_DIR}"/*.yaml |
  sed -E 's/^\$\{(.*)\}$/\1/' | sort -u)

if ((${#undefined[@]})); then
  echo "Undefined substitution variables (Flux would replace these with an empty string):" >&2
  printf '  ${%s}\n' "${undefined[@]}" >&2
  echo "Define them in ${SETTINGS_FILE}, or add them to EXTERNAL_VARS in $0." >&2
  exit 1
fi

echo "Substituting variables"
# Only the cluster-settings keys are replaced. Grafana dashboards carry
# expressions such as ${__field.name} that a general-purpose envsubst refuses to
# parse, and the resources holding them opt out of substitution anyway, so
# leaving every other ${...} untouched matches what the cluster gets.
for rendered in "${RENDER_DIR}"/*.yaml; do
  for var in "${setting_keys[@]}"; do
    sed -i "s|\${${var}}|${!var}|g" "${rendered}"
  done
done

echo "Validating against Kubernetes ${KUBERNETES_VERSION}"
# -strict rejects unknown fields, which is what catches a typo in a manifest.
# Secrets are skipped because SOPS adds a top-level `sops:` key that is not in
# the Secret schema; scripts/check-sops-encrypted.sh covers those instead.
# -ignore-missing-schemas keeps a brand new CRD from breaking CI before its
# schema is published upstream; those resources are reported as skipped.
kubeconform \
  -kubernetes-version "${KUBERNETES_VERSION}" \
  -schema-location default \
  -schema-location 'https://kubernetes-schemas.pages.dev/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  -strict \
  -skip Secret \
  -ignore-missing-schemas \
  -summary \
  -n 4 \
  "${RENDER_DIR}"
