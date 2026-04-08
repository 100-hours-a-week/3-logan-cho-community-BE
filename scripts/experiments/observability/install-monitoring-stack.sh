#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd aws
require_cmd python3

K6_INSTANCE_ID="${K6_INSTANCE_ID:-$(k6_instance_id)}"
APP_IP="${APP_PRIVATE_IP_OVERRIDE:-$(app_private_ip)}"
BUCKET="${S3_BUCKET_NAME_OVERRIDE:-$(bucket_name)}"
REMOTE_SCRIPT="/tmp/install-monitoring-stack.sh"
LOCAL_REMOTE_SCRIPT="/tmp/install-monitoring-stack.sh"
ASSET_DIR="${SCRIPT_DIR}/assets"
RENDER_DIR="$(mktemp -d)"
PROMETHEUS_VERSION="${PROMETHEUS_VERSION:-v2.52.0}"
GRAFANA_VERSION="${GRAFANA_VERSION:-11.1.0}"

cleanup() {
  rm -rf "${RENDER_DIR}" "${LOCAL_REMOTE_SCRIPT}"
}
trap cleanup EXIT

python3 - "${ASSET_DIR}/prometheus.yml.tpl" "${RENDER_DIR}/prometheus.yml" "${APP_IP}" <<'PY'
import pathlib
import sys

src = pathlib.Path(sys.argv[1]).read_text()
pathlib.Path(sys.argv[2]).write_text(src.replace("__APP_PUBLIC_IP__", sys.argv[3]))
PY

cp "${ASSET_DIR}/grafana-datasource.yml" "${RENDER_DIR}/grafana-datasource.yml"
cp "${ASSET_DIR}/grafana-dashboard-provider.yml" "${RENDER_DIR}/grafana-dashboard-provider.yml"
cp "${ASSET_DIR}/image-pipeline-overview.json" "${RENDER_DIR}/image-pipeline-overview.json"

aws s3 cp "${RENDER_DIR}/prometheus.yml" "s3://${BUCKET}/observability/prometheus.yml" >/dev/null
aws s3 cp "${RENDER_DIR}/grafana-datasource.yml" "s3://${BUCKET}/observability/grafana-datasource.yml" >/dev/null
aws s3 cp "${RENDER_DIR}/grafana-dashboard-provider.yml" "s3://${BUCKET}/observability/grafana-dashboard-provider.yml" >/dev/null
aws s3 cp "${RENDER_DIR}/image-pipeline-overview.json" "s3://${BUCKET}/observability/image-pipeline-overview.json" >/dev/null

cat > "${LOCAL_REMOTE_SCRIPT}" <<EOF
#!/bin/bash
set -euo pipefail

sudo dnf install -y docker
sudo systemctl enable docker
sudo systemctl restart docker

sudo mkdir -p /opt/experiment-observability/prometheus
sudo mkdir -p /opt/experiment-observability/grafana/provisioning/datasources
sudo mkdir -p /opt/experiment-observability/grafana/provisioning/dashboards
sudo mkdir -p /opt/experiment-observability/grafana/dashboards

sudo aws s3 cp s3://${BUCKET}/observability/prometheus.yml /opt/experiment-observability/prometheus/prometheus.yml
sudo aws s3 cp s3://${BUCKET}/observability/grafana-datasource.yml /opt/experiment-observability/grafana/provisioning/datasources/prometheus.yml
sudo aws s3 cp s3://${BUCKET}/observability/grafana-dashboard-provider.yml /opt/experiment-observability/grafana/provisioning/dashboards/dashboard.yml
sudo aws s3 cp s3://${BUCKET}/observability/image-pipeline-overview.json /opt/experiment-observability/grafana/dashboards/image-pipeline-overview.json

sudo docker rm -f experiment-prometheus experiment-grafana >/dev/null 2>&1 || true

sudo docker run -d \
  --name experiment-prometheus \
  --restart unless-stopped \
  -p 9090:9090 \
  -v /opt/experiment-observability/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
  prom/prometheus:${PROMETHEUS_VERSION} \
  --config.file=/etc/prometheus/prometheus.yml

sudo docker run -d \
  --name experiment-grafana \
  --restart unless-stopped \
  -p 3000:3000 \
  -e GF_SECURITY_ADMIN_USER=admin \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  -e GF_AUTH_ANONYMOUS_ENABLED=true \
  -e GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer \
  -e GF_USERS_DEFAULT_THEME=light \
  -v /opt/experiment-observability/grafana/provisioning:/etc/grafana/provisioning:ro \
  -v /opt/experiment-observability/grafana/dashboards:/var/lib/grafana/dashboards:ro \
  grafana/grafana-oss:${GRAFANA_VERSION}

for _ in \$(seq 1 30); do
  if curl -fsS http://127.0.0.1:9090/-/ready >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

for _ in \$(seq 1 45); do
  if curl -fsS http://127.0.0.1:3000/api/health >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

curl -fsS http://127.0.0.1:9090/-/ready
curl -fsS http://127.0.0.1:3000/api/health
EOF

chmod 700 "${LOCAL_REMOTE_SCRIPT}"
aws s3 cp "${LOCAL_REMOTE_SCRIPT}" "s3://${BUCKET}/observability/install-monitoring-stack.sh" >/dev/null

COMMAND_ID="$(ssm_send "${K6_INSTANCE_ID}" "install prometheus grafana" "[\"aws s3 cp s3://${BUCKET}/observability/install-monitoring-stack.sh ${REMOTE_SCRIPT}\",\"chmod +x ${REMOTE_SCRIPT}\",\"bash ${REMOTE_SCRIPT}\"]")"
STATUS="$(ssm_wait "${COMMAND_ID}")"
ssm_output "${COMMAND_ID}"

if [[ "${STATUS}" != "Success" ]]; then
  printf 'monitoring stack installation failed with status=%s\n' "${STATUS}" >&2
  exit 1
fi

log "monitoring stack installed on ${K6_INSTANCE_ID}"
