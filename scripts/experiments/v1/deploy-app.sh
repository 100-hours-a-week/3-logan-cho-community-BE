#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd scp
require_cmd ssh

APP_HOST="${APP_SSH_HOST_OVERRIDE:-$(app_ssh_host)}"
JAR_PATH="${PROJECT_ROOT}/build/libs/kaboocamPostProject-0.0.1-SNAPSHOT.jar"
ENV_PATH="${ENV_SCRIPT_PATH:-/tmp/experiment-app-env.sh}"
REMOTE_SCRIPT="~/remote-deploy-v1.sh"
LOCAL_REMOTE_SCRIPT="/tmp/remote-deploy-v1.sh"

ensure_file "${PROJECT_ROOT}/gradlew"
"${PROJECT_ROOT}/gradlew" bootJar >/dev/null
ensure_file "${JAR_PATH}"
S3_BUCKET_NAME_OVERRIDE="${S3_BUCKET_NAME_OVERRIDE:-$(bucket_name)}" "${SCRIPT_DIR}/render-app-env.sh" "${ENV_PATH}"
ensure_file "${ENV_PATH}"

ssh_run "${APP_HOST}" "mkdir -p /tmp/image-pipeline-upload"
scp_to "${JAR_PATH}" "${APP_HOST}" "/tmp/image-pipeline-upload/app.jar"
scp_to "${ENV_PATH}" "${APP_HOST}" "/tmp/image-pipeline-upload/experiment-app-env.sh"

cat > "${LOCAL_REMOTE_SCRIPT}" <<'EOF'
#!/bin/bash
set -euo pipefail
sudo dnf install -y docker java-17-amazon-corretto-headless
sudo systemctl enable docker
sudo systemctl restart docker
sudo docker rm -f mysql mongo redis >/dev/null 2>&1 || true
sudo docker volume prune -f >/dev/null 2>&1 || true
sudo pkill -f '/opt/image-pipeline/app.jar' || true
sudo docker run -d --name mysql \
  -e MYSQL_ROOT_PASSWORD=yourpw \
  -e MYSQL_DATABASE=millions \
  -e MYSQL_ROOT_HOST=% \
  -p 127.0.0.1:3306:3306 \
  mysql:8.4
sudo docker run -d --name mongo \
  -p 127.0.0.1:27017:27017 \
  mongo:latest --replSet rs0 --bind_ip_all
sudo docker run -d --name redis \
  -p 127.0.0.1:6379:6379 \
  redis:latest
for i in $(seq 1 60); do
  if sudo docker exec mysql mysqladmin ping -pyourpw --silent; then
    break
  fi
  sleep 2
done
for i in $(seq 1 60); do
  if sudo docker exec mongo mongosh --quiet --eval 'db.adminCommand({ ping: 1 }).ok' | grep -q 1; then
    break
  fi
  sleep 2
done
sudo docker exec mongo mongosh --quiet --eval 'try { rs.status().ok } catch (e) { rs.initiate({_id:"rs0", members:[{_id:0, host:"127.0.0.1:27017"}]}) }' >/dev/null 2>&1 || true
for i in $(seq 1 60); do
  if sudo docker exec mongo mongosh --quiet --eval 'try { print(rs.status().ok) } catch (e) { print(0) }' | grep -q 1; then
    break
  fi
  sleep 2
done
sudo mkdir -p /opt/image-pipeline
sudo mv /tmp/image-pipeline-upload/app.jar /opt/image-pipeline/app.jar
sudo mv /tmp/image-pipeline-upload/experiment-app-env.sh /opt/image-pipeline/experiment-app-env.sh
sudo chmod 700 /opt/image-pipeline/experiment-app-env.sh
sudo bash -lc 'source /opt/image-pipeline/experiment-app-env.sh && exec java -jar /opt/image-pipeline/app.jar >/opt/image-pipeline/app.log 2>&1 < /dev/null' >/dev/null 2>&1 &
echo $! | sudo tee /opt/image-pipeline/app.pid >/dev/null
sleep 20
sudo tail -n 120 /opt/image-pipeline/app.log
EOF

chmod 700 "${LOCAL_REMOTE_SCRIPT}"
scp_to "${LOCAL_REMOTE_SCRIPT}" "${APP_HOST}" "${REMOTE_SCRIPT}"
ssh_run "${APP_HOST}" "chmod +x ${REMOTE_SCRIPT} && bash ${REMOTE_SCRIPT}"

APP_IP="${APP_PUBLIC_IP_OVERRIDE:-$(app_public_ip)}"
for _ in $(seq 1 30); do
  if curl -fsS --max-time 5 "http://${APP_IP}:8080/api/health" >/dev/null 2>&1; then
    log "app health is ready at http://${APP_IP}:8080/api/health"
    exit 0
  fi
  sleep 2
done

printf 'app health check did not become ready: %s\n' "${APP_IP}" >&2
exit 1
