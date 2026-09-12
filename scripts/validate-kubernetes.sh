#!/usr/bin/env bash
# Renders every kustomization under kubernetes/ and validates the result against
# the Kubernetes API schemas plus the CRD schemas published by home-operations,
# then renders every HelmRelease's values against its own chart schema.
#
# Runs in CI on every pull request, which is what makes `ignoreTests: false` in
# .renovaterc.json5 mean something. Runnable locally the same way:
#
#   ./scripts/validate-kubernetes.sh
#
# The chart step pulls every chart, so it needs network access. Set
# SKIP_HELM_SCHEMA=1 to skip it.
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
  DISCORD_WEBHOOK_URL
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
# TalosUpgrade is skipped while the published schema lags the CRD tuppr installs:
# it lacks `waitForVolumeDetach` yet sets `additionalProperties: false`, so
# -strict rejects manifests a server-side dry-run accepts.
# -ignore-missing-schemas keeps a brand new CRD from breaking CI before its
# schema is published upstream; those resources are reported as skipped.
kubeconform \
  -kubernetes-version "${KUBERNETES_VERSION}" \
  -schema-location default \
  -schema-location 'https://kubernetes-schemas.pages.dev/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  -strict \
  -skip Secret,tuppr.home-operations.com/v1alpha1/TalosUpgrade \
  -ignore-missing-schemas \
  -summary \
  -n 4 \
  "${RENDER_DIR}"

# kubeconform validates the HelmRelease manifest but never the values it
# carries, so a key the chart's values.schema.json rejects only surfaces when
# Flux runs the install. Rendering each chart locally closes that gap.
if [[ -n "${SKIP_HELM_SCHEMA:-}" ]]; then
  echo "Skipping HelmRelease values validation (SKIP_HELM_SCHEMA is set)"
  exit 0
fi

for tool in helm yq; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "${tool} is required to validate HelmRelease values." >&2
    echo "Install it, or set SKIP_HELM_SCHEMA=1 to skip this step." >&2
    exit 1
  fi
done

echo "Validating HelmRelease values against chart schemas"
CHART_CACHE="${RENDER_DIR}/charts"
mkdir -p "${CHART_CACHE}"

# Sources are matched by name alone: a HelmRelease may reference a repository
# declared in another namespace, and the rendered output does not always carry
# one (targetNamespace is set by the parent Flux Kustomization).
declare -A SRC_URL SRC_TAG
while IFS=$'\t' read -r kind name url tag; do
  [[ -n "${name}" ]] || continue
  SRC_URL["${kind}/${name}"]="${url}"
  SRC_TAG["${kind}/${name}"]="${tag}"
done < <(yq -N '. | select(.kind == "OCIRepository" or .kind == "HelmRepository")
                | [.kind, .metadata.name, .spec.url, (.spec.ref.tag // "")] | @tsv' \
  "${RENDER_DIR}"/*.yaml 2>/dev/null | sort -u)

helm_failed=0
declare -A SEEN
while IFS=$'\t' read -r file name refkind refname chart version srcname; do
  [[ -n "${name}" && -z "${SEEN[${name}]:-}" ]] || continue
  SEEN["${name}"]=1

  if [[ "${refkind}" != "-" ]]; then
    url="${SRC_URL[${refkind}/${refname}]:-}"
    version="${SRC_TAG[${refkind}/${refname}]:-}"
    chart="${url##*/}"
    pull_args=("${url}" --version "${version}")
  else
    url="${SRC_URL[HelmRepository/${srcname}]:-}"
    pull_args=("${chart}" --repo "${url}")
    [[ "${version}" == "-" ]] || pull_args+=(--version "${version}")
  fi

  if [[ -z "${url}" ]]; then
    echo "  ? ${name}: chart source not found in the rendered output, skipped" >&2
    continue
  fi

  dir="${CHART_CACHE}/${name}"
  if ! helm pull "${pull_args[@]}" -d "${dir}" --untar >/dev/null 2>&1; then
    echo "  ? ${name}: could not pull ${url}, skipped" >&2
    continue
  fi

  yq -N "select(.kind == \"HelmRelease\" and .metadata.name == \"${name}\")
         | .spec.values" "${file}" >"${RENDER_DIR}/values.yaml"

  # Template failures have many causes that do not apply in-cluster, chiefly
  # values Flux supplies from a Secret through valuesFrom. Only a schema
  # violation is unambiguous, so only that one fails the run.
  if ! out="$(helm template "${name}" "${dir}/${chart}" -f "${RENDER_DIR}/values.yaml" 2>&1)"; then
    if grep -qF "don't meet the specifications of the schema" <<<"${out}"; then
      echo "  ✗ ${name}: values rejected by the chart schema" >&2
      grep -E "^(-| at )" <<<"${out}" | sed 's/^/      /' >&2
      helm_failed=1
    else
      echo "  ? ${name}: helm template failed for another reason, not a schema error" >&2
    fi
  fi
done < <(for f in "${RENDER_DIR}"/*.yaml; do
  yq -N "select(.kind == \"HelmRelease\" and .spec.values != null)
         | [\"${f}\", .metadata.name, (.spec.chartRef.kind // \"-\"),
            (.spec.chartRef.name // \"-\"), (.spec.chart.spec.chart // \"-\"),
            (.spec.chart.spec.version // \"-\"),
            (.spec.chart.spec.sourceRef.name // \"-\")] | @tsv" "${f}" 2>/dev/null
done)

if ((helm_failed)); then
  echo "HelmRelease values rejected by their chart schema." >&2
  exit 1
fi

