#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd aws

APP_INSTANCE_ID="${APP_INSTANCE_ID:-$(app_instance_id)}"
BUCKET="${S3_BUCKET_NAME_OVERRIDE:-$(bucket_name)}"
REMOTE_SCRIPT="/tmp/install-node-exporter.sh"
LOCAL_REMOTE_SCRIPT="/tmp/install-node-exporter.sh"
NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-1.8.2}"

cat > "${LOCAL_REMOTE_SCRIPT}" <<EOF
#!/bin/bash
set -euo pipefail

VERSION="${NODE_EXPORTER_VERSION}"
ARCHIVE="node_exporter-\${VERSION}.linux-amd64.tar.gz"
URL="https://github.com/prometheus/node_exporter/releases/download/v\${VERSION}/\${ARCHIVE}"

sudo dnf install -y tar
if ! id -u node_exporter >/dev/null 2>&1; then
  sudo useradd --system --no-create-home --shell /sbin/nologin node_exporter
fi

cd /tmp
rm -rf "node_exporter-\${VERSION}.linux-amd64" "\${ARCHIVE}"
curl -fsSL -o "\${ARCHIVE}" "\${URL}"
tar -xzf "\${ARCHIVE}"
sudo install -m 0755 "node_exporter-\${VERSION}.linux-amd64/node_exporter" /usr/local/bin/node_exporter

sudo tee /etc/systemd/system/node_exporter.service >/dev/null <<'SERVICE'
[Unit]
Description=Prometheus Node Exporter
After=network-online.target
Wants=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
sleep 3
curl -fsS http://127.0.0.1:9100/metrics | sed -n '1,5p'
EOF

chmod 700 "${LOCAL_REMOTE_SCRIPT}"
aws s3 cp "${LOCAL_REMOTE_SCRIPT}" "s3://${BUCKET}/observability/install-node-exporter.sh" >/dev/null

COMMAND_ID="$(ssm_send "${APP_INSTANCE_ID}" "install node exporter" "[\"aws s3 cp s3://${BUCKET}/observability/install-node-exporter.sh ${REMOTE_SCRIPT}\",\"chmod +x ${REMOTE_SCRIPT}\",\"bash ${REMOTE_SCRIPT}\"]")"
STATUS="$(ssm_wait "${COMMAND_ID}")"
ssm_output "${COMMAND_ID}"

if [[ "${STATUS}" != "Success" ]]; then
  printf 'node_exporter installation failed with status=%s\n' "${STATUS}" >&2
  exit 1
fi

log "node_exporter installed on ${APP_INSTANCE_ID}"
