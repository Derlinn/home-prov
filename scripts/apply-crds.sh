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
    ["keda"]="oci://ghcr.io/home-operations/charts-mirror/keda"
    ["kube-prometheus-stack"]="oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack"
)

declare -A CHARTS_VERSION=(
    ["cloudflare-dns"]="1.19.0"
    ["envoy-gateway"]="v1.6.0"
    ["grafana-operator"]="v5.20.0"
    ["keda"]="2.18.1"
    ["kube-prometheus-stack"]="79.7.1"
)

declare -A CHARTS_NAMESPACE=(
    ["cloudflare-dns"]="network"
    ["envoy-gateway"]="network"
    ["grafana-operator"]="observability"
    ["keda"]="observability"
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
        --kube-version 1.31.0 \
        | yq ea -e 'select(.kind == "CustomResourceDefinition")' \
        | kubectl apply --server-side --field-manager bootstrap --force-conflicts -f -; then
        log_info "✓ CRDs applied successfully for $chart_name"
    else
        log_warn "✗ No CRDs found or failed to apply for $chart_name (this might be normal)"
    fi

    echo ""
done

log_info "CRDs application completed!"
