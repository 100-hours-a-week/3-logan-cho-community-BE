#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <user@host> [remote_dir]"
  exit 1
fi

REMOTE_HOST="$1"
REMOTE_DIR="${2:-~/cf-private-content-benchmark}"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date -u +"%Y%m%dT%H%M%SZ")"
DEST_DIR="${BASE_DIR}/results/remote/${TIMESTAMP}"

mkdir -p "${DEST_DIR}"

scp -r "${REMOTE_HOST}:${REMOTE_DIR}/results/raw" "${DEST_DIR}/"
scp -r "${REMOTE_HOST}:${REMOTE_DIR}/results/summary" "${DEST_DIR}/"

echo "Fetched remote results into ${DEST_DIR}"
