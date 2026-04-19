#!/bin/sh
set -eu

NODE_EXPORTER_VERSION="1.8.2"
SMARTCTL_EXPORTER_VERSION="0.13.0"
INSTALL_DIR="/usr/local/bin"
ARCH="arm64"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root" >&2
  exit 1
fi

# --- node_exporter ---

echo ">> Installing node_exporter ${NODE_EXPORTER_VERSION}..."
curl -fsSL "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}.tar.gz" \
  | tar -xz -C /tmp
install -m 0755 "/tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}/node_exporter" "${INSTALL_DIR}/node_exporter"
rm -rf "/tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-${ARCH}"

# --- smartctl_exporter ---

echo ">> Installing smartctl_exporter ${SMARTCTL_EXPORTER_VERSION}..."
curl -fsSL "https://github.com/prometheus-community/smartctl_exporter/releases/download/v${SMARTCTL_EXPORTER_VERSION}/smartctl_exporter-${SMARTCTL_EXPORTER_VERSION}.linux-${ARCH}.tar.gz" \
  | tar -xz -C /tmp
install -m 0755 "/tmp/smartctl_exporter-${SMARTCTL_EXPORTER_VERSION}.linux-${ARCH}/smartctl_exporter" "${INSTALL_DIR}/smartctl_exporter"
rm -rf "/tmp/smartctl_exporter-${SMARTCTL_EXPORTER_VERSION}.linux-${ARCH}"

# --- startup via cron @reboot ---

echo ">> Registering cron @reboot entries..."
crontab -l 2>/dev/null | grep -v 'node_exporter\|smartctl_exporter' > /tmp/crontab.tmp || true

cat >> /tmp/crontab.tmp <<'EOF'
@reboot /usr/local/bin/node_exporter --collector.diskstats --collector.filesystem --collector.netdev --collector.meminfo --collector.cpu --web.listen-address=:9100 >/dev/null 2>&1 &
@reboot /usr/local/bin/smartctl_exporter --web.listen-address=:9633 --smartctl.interval=120s --smartctl.path=/usr/builtin/sbin/smartctl >/dev/null 2>&1 &
EOF

crontab /tmp/crontab.tmp
rm /tmp/crontab.tmp

# --- start now ---

echo ">> Starting services..."
/usr/local/bin/node_exporter --collector.diskstats --collector.filesystem --collector.netdev --collector.meminfo --collector.cpu --web.listen-address=:9100 >/dev/null 2>&1 &
/usr/local/bin/smartctl_exporter --web.listen-address=:9633 --smartctl.interval=120s --smartctl.path=/usr/builtin/sbin/smartctl >/dev/null 2>&1 &

sleep 2
echo ""
echo ">> Status:"
curl -sf http://localhost:9100/metrics >/dev/null 2>&1 && echo "  node_exporter     OK (port 9100)" || echo "  node_exporter     FAILED"
curl -sf http://localhost:9633/metrics >/dev/null 2>&1 && echo "  smartctl_exporter OK (port 9633)" || echo "  smartctl_exporter FAILED"
