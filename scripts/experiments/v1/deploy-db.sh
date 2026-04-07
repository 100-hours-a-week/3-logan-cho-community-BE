#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

require_cmd scp
require_cmd ssh

DB_HOST="${DB_SSH_HOST_OVERRIDE:-$(db_ssh_host)}"
DB_PRIVATE_IP="${DB_PRIVATE_IP_OVERRIDE:-$(db_private_ip)}"
REMOTE_SCRIPT="~/remote-deploy-db.sh"
LOCAL_REMOTE_SCRIPT="/tmp/remote-deploy-db.sh"

if [[ -z "${DB_HOST}" || "${DB_HOST}" == "null" ]]; then
  printf 'db host is missing.\n' >&2
  exit 1
fi

cat > "${LOCAL_REMOTE_SCRIPT}" <<EOF
#!/bin/bash
set -euo pipefail
sudo dnf install -y docker
sudo systemctl enable docker
sudo systemctl restart docker
sudo docker rm -f mysql mongo redis >/dev/null 2>&1 || true
sudo docker volume prune -f >/dev/null 2>&1 || true
sudo docker run -d --name mysql \
  -e MYSQL_ROOT_PASSWORD=yourpw \
  -e MYSQL_DATABASE=millions \
  -e MYSQL_ROOT_HOST=% \
  -p 0.0.0.0:3306:3306 \
  mysql:8.4
sudo docker run -d --name mongo \
  -p 0.0.0.0:27017:27017 \
  mongo:latest --replSet rs0 --bind_ip_all
sudo docker run -d --name redis \
  -p 0.0.0.0:6379:6379 \
  redis:latest
for i in \$(seq 1 60); do
  if sudo docker exec mysql mysqladmin ping -pyourpw --silent; then
    break
  fi
  sleep 2
done
for i in \$(seq 1 60); do
  if sudo docker exec mongo mongosh --quiet --eval 'db.adminCommand({ ping: 1 }).ok' | grep -q 1; then
    break
  fi
  sleep 2
done
sudo docker exec mongo mongosh --quiet --eval 'try { rs.status().ok } catch (e) { rs.initiate({_id:"rs0", members:[{_id:0, host:"${DB_PRIVATE_IP}:27017"}]}) }' >/dev/null 2>&1 || true
for i in \$(seq 1 60); do
  if sudo docker exec mongo mongosh --quiet --eval 'try { print(rs.status().ok) } catch (e) { print(0) }' | grep -q 1; then
    break
  fi
  sleep 2
done
sudo docker exec mysql mysql -uroot -pyourpw -e 'DROP DATABASE IF EXISTS millions; CREATE DATABASE millions;' >/dev/null 2>&1 || true
sudo docker exec mongo mongosh --quiet --eval 'db.getSiblingDB("millions").dropDatabase()' >/dev/null 2>&1 || true
EOF

chmod 700 "${LOCAL_REMOTE_SCRIPT}"
scp_to "${LOCAL_REMOTE_SCRIPT}" "${DB_HOST}" "${REMOTE_SCRIPT}"
ssh_run "${DB_HOST}" "chmod +x ${REMOTE_SCRIPT} && bash ${REMOTE_SCRIPT}"

log "db host is ready at ${DB_PRIVATE_IP}"
