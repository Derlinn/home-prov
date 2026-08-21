#!/usr/bin/env bash
# Installs node_exporter on the Proxmox host. It has to run on the host itself:
# in a container lxcfs shows the container's /proc, not the machine's, so CPU,
# memory, disks and temperatures would all be wrong.
#
# The Proxmox API is scraped separately by prometheus-pve-exporter, which runs
# in the cluster (kubernetes/apps/observability/proxmox).
#
# Usage, as root on lin-prx-01:
#   ./proxmox-exporters-install.sh
set -euo pipefail

# renovate: datasource=github-releases depName=prometheus/node_exporter
NODE_EXPORTER_VERSION="1.12.1"
ARCH="amd64"
INSTALL_DIR="/usr/local/bin"

if [[ $EUID -ne 0 ]]; then
    echo "Run as root" >&2
    exit 1
fi

echo ">> Installing node_exporter ${NODE_EXPORTER_VERSION} (${ARCH})..."
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
curl -fsSL "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}.tar.gz" \
    | tar -xz -C "${tmp}"
install -m 0755 "${tmp}/node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}/node_exporter" "${INSTALL_DIR}/node_exporter"

if ! id -u node_exporter >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter
fi

echo ">> Writing systemd unit..."
cat > /etc/systemd/system/node_exporter.service <<'EOF'
[Unit]
Description=Prometheus node_exporter
After=network-online.target
Wants=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
# hwmon gives CPU and board temperatures, which is the point of monitoring a
# tower. textfile lets Proxmox hook scripts drop extra metrics in later.
ExecStart=/usr/local/bin/node_exporter \
    --collector.systemd \
    --collector.hwmon \
    --collector.textfile.directory=/var/lib/node_exporter/textfile \
    --web.listen-address=:9100
Restart=on-failure
RestartSec=5
ProtectSystem=strict
ProtectHome=yes
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF

install -d -o node_exporter -g node_exporter /var/lib/node_exporter/textfile

systemctl daemon-reload
systemctl enable --now node_exporter

sleep 2
echo ""
echo ">> Status:"
if curl -sf http://localhost:9100/metrics >/dev/null 2>&1; then
    echo "  node_exporter  OK (port 9100)"
else
    echo "  node_exporter  FAILED"
    systemctl status node_exporter --no-pager || true
    exit 1
fi
