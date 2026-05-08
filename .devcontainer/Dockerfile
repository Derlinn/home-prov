FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG DEBIAN_FRONTEND=noninteractive

# ── Versions (mirrored from .mise.toml) ──────────────────────────────────────
ARG PYTHON_VERSION=3.14
ARG KUBECTL_VERSION=1.34.0
ARG HELM_VERSION=3.19.2
ARG HELMFILE_VERSION=1.1.9
ARG KUSTOMIZE_VERSION=5.7.1
ARG FLUX_VERSION=2.7.3
ARG K9S_VERSION=0.32.5
ARG KUBECTX_VERSION=0.9.5
ARG CILIUM_CLI_VERSION=0.18.8
ARG HUBBLE_VERSION=1.18.6
ARG TALHELPER_VERSION=3.0.39
ARG TALOSCTL_VERSION=1.11.5
ARG SOPS_VERSION=3.11.0
ARG JQ_VERSION=1.8.1
ARG YQ_VERSION=4.48.2
ARG GH_VERSION=2.83.1
ARG CLOUDFLARED_VERSION=2025.11.1
ARG KUBE_PS1_VERSION=0.9.0
# Not in .mise.toml but required by Taskfile + pre-commit hooks — update as needed
ARG TERRAFORM_VERSION=1.9.8
ARG TASK_VERSION=3.37.0

# ── System packages ───────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        software-properties-common \
        curl \
        wget \
        git \
        unzip \
        gnupg \
        ca-certificates \
        libssl-dev \
        libffi-dev \
        zlib1g-dev \
        libbz2-dev \
        libreadline-dev \
        libsqlite3-dev \
        liblzma-dev \
        libncurses-dev \
        python3-pip \
    && rm -rf /var/lib/apt/lists/*

# ── Python 3.14 ───────────────────────────────────────────────────────────────
# Install alongside the system Python (3.12) without replacing it — the
# devcontainer base image's init scripts depend on the system python3.
RUN add-apt-repository ppa:deadsnakes/ppa -y \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-venv \
        python${PYTHON_VERSION}-dev \
    && rm -rf /var/lib/apt/lists/*

# ── pre-commit ────────────────────────────────────────────────────────────────
RUN pip3 install --break-system-packages pre-commit

# ── kubectl ───────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
        -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# ── helm ──────────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
    | tar -xz --strip-components=1 -C /usr/local/bin linux-amd64/helm

# ── helmfile ──────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://github.com/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION}_linux_amd64.tar.gz" \
    | tar -xz -C /usr/local/bin helmfile

# ── kustomize ─────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" \
    | tar -xz -C /usr/local/bin kustomize

# ── flux ──────────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}/flux_${FLUX_VERSION}_linux_amd64.tar.gz" \
    | tar -xz -C /usr/local/bin flux

# ── k9s ───────────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_Linux_amd64.tar.gz" \
    | tar -xz -C /usr/local/bin k9s

# ── kubectx & kubens ──────────────────────────────────────────────────────────
RUN curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubectx_v${KUBECTX_VERSION}_linux_x86_64.tar.gz" \
    | tar -xz -C /usr/local/bin kubectx \
    && curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/v${KUBECTX_VERSION}/kubens_v${KUBECTX_VERSION}_linux_x86_64.tar.gz" \
    | tar -xz -C /usr/local/bin kubens

# ── cilium-cli ────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://github.com/cilium/cilium-cli/releases/download/v${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz" \
    | tar -xz -C /usr/local/bin cilium

# ── hubble ────────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://github.com/cilium/hubble/releases/download/v${HUBBLE_VERSION}/hubble-linux-amd64.tar.gz" \
    | tar -xz -C /usr/local/bin hubble

# ── talhelper ─────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://github.com/budimanjojo/talhelper/releases/download/v${TALHELPER_VERSION}/talhelper_linux_amd64.tar.gz" \
    | tar -xz -C /usr/local/bin talhelper

# ── talosctl ──────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://github.com/siderolabs/talos/releases/download/v${TALOSCTL_VERSION}/talosctl-linux-amd64" \
        -o /usr/local/bin/talosctl \
    && chmod +x /usr/local/bin/talosctl

# ── sops ──────────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64" \
        -o /usr/local/bin/sops \
    && chmod +x /usr/local/bin/sops

# ── jq ────────────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64" \
        -o /usr/local/bin/jq \
    && chmod +x /usr/local/bin/jq

# ── yq ────────────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" \
        -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

# ── gh (GitHub CLI) ───────────────────────────────────────────────────────────
RUN TMPDIR=$(mktemp -d) \
    && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
        | tar -xz -C "$TMPDIR" \
    && mv "$TMPDIR/gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh \
    && rm -rf "$TMPDIR"

# ── cloudflared ───────────────────────────────────────────────────────────────
RUN curl -fsSL "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-amd64" \
        -o /usr/local/bin/cloudflared \
    && chmod +x /usr/local/bin/cloudflared

# ── terraform ─────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
        -o /tmp/terraform.zip \
    && unzip /tmp/terraform.zip -d /usr/local/bin \
    && rm /tmp/terraform.zip

# ── go-task ───────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://github.com/go-task/task/releases/download/v${TASK_VERSION}/task_linux_amd64.tar.gz" \
    | tar -xz -C /usr/local/bin task

# ── kube-ps1 ──────────────────────────────────────────────────────────────────
RUN TMPDIR=$(mktemp -d) \
    && curl -fsSL "https://github.com/jonmosco/kube-ps1/archive/refs/tags/v${KUBE_PS1_VERSION}.tar.gz" \
        | tar -xz -C "$TMPDIR" \
    && cp "$TMPDIR/kube-ps1-${KUBE_PS1_VERSION}/kube-ps1.sh" /usr/local/bin/kube-ps1.sh \
    && chmod +x /usr/local/bin/kube-ps1.sh \
    && rm -rf "$TMPDIR"
