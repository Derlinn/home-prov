#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Chart definitions
declare -A CHARTS_URL=(
    ["cloudflare-dns"]="oci://ghcr.io/home-operations/charts-mirror/external-dns"
    ["envoy-gateway"]="oci://mirror.gcr.io/envoyproxy/gateway-helm"
    ["grafana-operator"]="oci://ghcr.io/grafana/helm-charts/grafana-operator"
    ["kube-prometheus-stack"]="oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack"
)

# Keep these in sync with the matching OCIRepository under kubernetes/apps.
# This script pre-applies CRDs before Flux takes over, so a stale version here
# installs CRDs older than the chart that will own them.
declare -A CHARTS_VERSION=(
    # renovate: datasource=docker depName=ghcr.io/home-operations/charts-mirror/external-dns
    ["cloudflare-dns"]="1.21.1"
    # renovate: datasource=docker depName=mirror.gcr.io/envoyproxy/gateway-helm
    ["envoy-gateway"]="v1.9.0"
    # renovate: datasource=docker depName=ghcr.io/grafana/helm-charts/grafana-operator
    ["grafana-operator"]="5.25.0"
    # renovate: datasource=docker depName=ghcr.io/prometheus-community/charts/kube-prometheus-stack
    ["kube-prometheus-stack"]="88.1.5"
)

declare -A CHARTS_NAMESPACE=(
    ["cloudflare-dns"]="network"
    ["envoy-gateway"]="network"
    ["grafana-operator"]="observability"
    ["kube-prometheus-stack"]="observability"
)

# Check required tools
for tool in helm kubectl yq; do
    if ! command -v $tool &> /dev/null; then
        log_error "$tool is not installed. Please install it first."
        exit 1
    fi
done

log_info "Starting CRDs application..."

# Derived from the live cluster rather than pinned: charts gate CRD fields on
# the target Kubernetes version, and a stale pin renders CRDs for an API level
# the cluster left behind long ago.
KUBE_VERSION="$(kubectl version -o json 2>/dev/null | yq -r '.serverVersion.gitVersion')"
if [[ -z "${KUBE_VERSION}" || "${KUBE_VERSION}" == "null" ]]; then
    log_error "Could not read the cluster Kubernetes version. Is the kubeconfig valid?"
    exit 1
fi
log_info "Templating charts against Kubernetes ${KUBE_VERSION}"

# Apply CRDs from each chart
for chart_name in "${!CHARTS_URL[@]}"; do
    chart_url="${CHARTS_URL[$chart_name]}"
    version="${CHARTS_VERSION[$chart_name]}"
    namespace="${CHARTS_NAMESPACE[$chart_name]}"

    log_info "Processing $chart_name from $chart_url:$version"

    # Template the chart and filter CRDs
    if helm template "$chart_name" \
        "$chart_url" \
        --version "$version" \
        --namespace "$namespace" \
        --include-crds \
        --kube-version "${KUBE_VERSION}" \
        | yq ea -e 'select(.kind == "CustomResourceDefinition")' \
        | kubectl apply --server-side --field-manager bootstrap --force-conflicts -f -; then
        log_info "✓ CRDs applied successfully for $chart_name"
    else
        log_warn "✗ No CRDs found or failed to apply for $chart_name (this might be normal)"
    fi

    echo ""
done

log_info "CRDs application completed!"
