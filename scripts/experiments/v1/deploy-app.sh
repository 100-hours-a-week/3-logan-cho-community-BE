#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd scp
require_cmd ssh
require_cmd curl
require_cmd aws

JAR_PATH="${PROJECT_ROOT}/build/libs/kaboocamPostProject-0.0.1-SNAPSHOT.jar"
ENV_PATH="${ENV_SCRIPT_PATH:-/tmp/experiment-app-env.sh}"
LOCAL_REMOTE_SCRIPT="/tmp/remote-deploy-app.sh"
REMOTE_SCRIPT="~/remote-deploy-app.sh"
BUCKET="${S3_BUCKET_NAME_OVERRIDE:-$(bucket_name)}"

ensure_file "${PROJECT_ROOT}/gradlew"
"${PROJECT_ROOT}/gradlew" bootJar >/dev/null
ensure_file "${JAR_PATH}"

if [[ -n "$(db_instance_id)" && "$(db_instance_id)" != "null" ]]; then
  "${SCRIPT_DIR}/deploy-db.sh"
  export DB_PRIVATE_IP_OVERRIDE="${DB_PRIVATE_IP_OVERRIDE:-$(db_private_ip)}"
fi

S3_BUCKET_NAME_OVERRIDE="${S3_BUCKET_NAME_OVERRIDE:-$(bucket_name)}" "${SCRIPT_DIR}/render-app-env.sh" "${ENV_PATH}"
ensure_file "${ENV_PATH}"

if ! aws s3 cp "${JAR_PATH}" "s3://${BUCKET}/artifacts/kaboocamPostProject-0.0.1-SNAPSHOT.jar" >/dev/null 2>&1; then
  upload_to_s3_via_instance_role "${JAR_PATH}" "$(app_ssh_host)" "s3://${BUCKET}/artifacts/kaboocamPostProject-0.0.1-SNAPSHOT.jar"
fi

if ! aws s3 cp "${ENV_PATH}" "s3://${BUCKET}/artifacts/experiment-app-env.sh" >/dev/null 2>&1; then
  upload_to_s3_via_instance_role "${ENV_PATH}" "$(app_ssh_host)" "s3://${BUCKET}/artifacts/experiment-app-env.sh"
fi

if [[ -n "$(app_asg_name)" && "$(app_asg_name)" != "null" ]]; then
  while IFS= read -r app_host; do
    [[ -z "${app_host}" ]] && continue
    ssh_run "${app_host}" "
if sudo test -f /etc/systemd/system/experiment-app.service; then
  sudo systemctl restart experiment-app.service
else
  sudo pkill -f '/opt/image-pipeline/app.jar' || true
  sudo bash -lc 'source /opt/image-pipeline/experiment-app-env.sh && exec java -jar /opt/image-pipeline/app.jar >/opt/image-pipeline/app.log 2>&1 < /dev/null' >/dev/null 2>&1 &
  echo \$! | sudo tee /opt/image-pipeline/app.pid >/dev/null
fi
sleep 5
sudo tail -n 80 /opt/image-pipeline/app.log || true
"
  done < <(app_public_ips)
else
cat > "${LOCAL_REMOTE_SCRIPT}" <<'EOF'
#!/bin/bash
set -euo pipefail
sudo dnf install -y java-17-amazon-corretto-headless docker
sudo systemctl enable docker >/dev/null 2>&1 || true
sudo systemctl restart docker >/dev/null 2>&1 || true
sudo pkill -f '/opt/image-pipeline/app.jar' || true
sudo mkdir -p /opt/image-pipeline
sudo mv /tmp/image-pipeline-upload/app.jar /opt/image-pipeline/app.jar
sudo mv /tmp/image-pipeline-upload/experiment-app-env.sh /opt/image-pipeline/experiment-app-env.sh
sudo chmod 700 /opt/image-pipeline/experiment-app-env.sh
sudo bash -lc 'source /opt/image-pipeline/experiment-app-env.sh && exec java -jar /opt/image-pipeline/app.jar >/opt/image-pipeline/app.log 2>&1 < /dev/null' >/dev/null 2>&1 &
echo $! | sudo tee /opt/image-pipeline/app.pid >/dev/null
sleep 10
sudo tail -n 80 /opt/image-pipeline/app.log || true
EOF

chmod 700 "${LOCAL_REMOTE_SCRIPT}"

while IFS= read -r app_host; do
  [[ -z "${app_host}" ]] && continue
  ssh_run "${app_host}" "mkdir -p /tmp/image-pipeline-upload"
  scp_to "${JAR_PATH}" "${app_host}" "/tmp/image-pipeline-upload/app.jar"
  scp_to "${ENV_PATH}" "${app_host}" "/tmp/image-pipeline-upload/experiment-app-env.sh"
  scp_to "${LOCAL_REMOTE_SCRIPT}" "${app_host}" "${REMOTE_SCRIPT}"
  ssh_run "${app_host}" "chmod +x ${REMOTE_SCRIPT} && bash ${REMOTE_SCRIPT}"
done < <(app_public_ips)
fi

APP_URL="${APP_URL_OVERRIDE:-$(app_base_url)}"
for _ in $(seq 1 40); do
  if curl -fsS --max-time 5 "${APP_URL}/api/health" >/dev/null 2>&1; then
    log "app health is ready at ${APP_URL}/api/health"
    exit 0
  fi
  sleep 3
done

printf 'app health check did not become ready: %s\n' "${APP_URL}" >&2
exit 1
