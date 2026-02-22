#!/bin/bash
set -euxo pipefail

echo "=========================================="
echo "Starting Golden AMI setup"
echo "=========================================="

apt-get update
apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  unzip

# Install Docker Engine + Compose plugin
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# Install AWS CLI v2
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/aws /tmp/awscliv2.zip

# SSM Agent is preinstalled in Ubuntu 22.04 AMI, make sure it is enabled
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service || true

# Install ECR credential helper
apt-get install -y amazon-ecr-credential-helper

mkdir -p /home/ubuntu/.docker
cat > /home/ubuntu/.docker/config.json <<'JSON'
{
  "credsStore": "ecr-login"
}
JSON
chown -R ubuntu:ubuntu /home/ubuntu/.docker

mkdir -p /root/.docker
cat > /root/.docker/config.json <<'JSON'
{
  "credsStore": "ecr-login"
}
JSON

# Runtime directories
mkdir -p /opt/monitoring /opt/app /var/log/app
chmod 755 /var/log/app
chown ubuntu:ubuntu /var/log/app

# Copy monitoring and app bootstrap files
cp -r /tmp/monitoring/* /opt/monitoring/
cp -r /tmp/app/* /opt/app/

if [ -n "${LOKI_URL:-}" ]; then
  sed -i "s|http://loki:3100/loki/api/v1/push|${LOKI_URL}|g" /opt/monitoring/promtail-config.yaml
fi

cat > /etc/default/monitoring.template <<'EOT'
# Promtail label name
APP_NAME=backend
EOT

cat > /etc/default/kaboocam-app.template <<'EOT'
# Fill and copy to /etc/default/kaboocam-app by user_data
APP_IMAGE=123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/kaboocam-post:latest
SPRING_PROFILES_ACTIVE=prod
SERVER_PORT=8080
TZ=Asia/Seoul
JAVA_TOOL_OPTIONS=-Xms256m -Xmx512m
EOT

# Register systemd services
cp /tmp/monitoring.service /etc/systemd/system/monitoring.service
cp /tmp/app.service /etc/systemd/system/app.service
chmod 644 /etc/systemd/system/monitoring.service /etc/systemd/system/app.service
systemctl daemon-reload

# Monitoring can run out-of-the-box, app service requires /etc/default/kaboocam-app runtime values.
systemctl enable monitoring.service
systemctl disable app.service || true

# Pre-pull monitoring images for faster first boot
docker pull prom/node-exporter:latest || true
docker pull gcr.io/cadvisor/cadvisor:latest || true
docker pull grafana/promtail:latest || true

echo "=========================================="
echo "Golden AMI setup complete"
echo "=========================================="
