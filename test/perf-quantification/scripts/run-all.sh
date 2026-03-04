#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

RUN_EXPERIMENTS="${RUN_EXPERIMENTS:-01,03,05}"

log "실행 대상 실험: ${RUN_EXPERIMENTS}"
for exp in ${RUN_EXPERIMENTS//,/ }; do
  case "${exp}" in
    01)
      log "01: Next-Key Lock 실험 시작"
      "${SCRIPT_DIR}/run-exp01-next-key-lock.sh"
      ;;
    03)
      log "03: 조회수 배치 반영 실험 시작"
      "${SCRIPT_DIR}/run-exp03-view-counter-batch.sh"
      ;;
    05)
      log "05: Redis Pipeline 실험 시작"
      "${SCRIPT_DIR}/run-exp05-redis-pipeline.sh"
      ;;
    *)
      warn "미지원 실험 ID: ${exp}"
      ;;
  esac
  echo
done

log "실험 완료"
