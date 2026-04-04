#!/usr/bin/env bash

set -euo pipefail

cat <<'EOF'
capture-spring-cpu.sh is deprecated.

Use Prometheus + Grafana as the fixed metric collection method for:
- App EC2 host CPU
- Spring CPU

Reference:
- docs/experiments/observability.md
EOF

exit 1
