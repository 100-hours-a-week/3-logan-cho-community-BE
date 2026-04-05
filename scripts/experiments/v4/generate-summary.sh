#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

python3 - "${PROJECT_ROOT}" <<'PY'
import json
import pathlib
import statistics
import sys

root = pathlib.Path(sys.argv[1])
k6_dir = root / "docs/experiments/results/exp-v4-idempotent/k6"
metrics_dir = root / "docs/experiments/results/exp-v4-idempotent/metrics"
summary_path = root / "docs/experiments/results/exp-v4-idempotent/summary.md"
report_path = root / "docs/experiments/results/exp-v4-idempotent/v4-baseline-report-2026-04-05.md"
scenario_names = ["medium_10rps", "heavy_20rps", "burst_5_to_30"]

def metric_value(metrics, name, field, default=None):
    metric = metrics.get(name)
    if not metric:
        return default
    return metric.get(field, default)

def safe_mean(values):
    values = [v for v in values if v is not None]
    if not values:
        return None
    return statistics.mean(values)

def fmt(value, digits=2):
    if value is None:
        return "n/a"
    return f"{value:.{digits}f}"

summary_lines = [
    "# exp-v4-idempotent Summary",
    "",
    "실행 일시:",
    "- 2026-04-05",
    "",
    "실행 기준:",
    "- 브랜치: `experiment/image-pipeline-evolution`",
    "- 반복: 시나리오별 3회",
    "- 1차 비교 지표: `k6` 기준 `POST /posts p95`, `API error rate`",
    "- 추가 지표: `image completion latency p95`, `duplicate side effect count`, `DLQ count`",
    "",
    "원본 결과:",
    "- `docs/experiments/results/exp-v4-idempotent/k6/*-summary.json`",
    "- `docs/experiments/results/exp-v4-idempotent/k6/*-stdout.log`",
    "- `docs/experiments/results/exp-v4-idempotent/metrics/*.json`",
    "",
    "## Scenario Results",
    "",
]

table_rows = []
for scenario in scenario_names:
    k6_samples = []
    processed_samples = []
    dlq_samples = []
    for i in range(1, 4):
        summary_file = k6_dir / f"{scenario}-run{i}-summary.json"
        processed_file = metrics_dir / f"processed-{scenario}-run{i}.json"
        dlq_file = metrics_dir / f"dlq-{scenario}-run{i}.json"
        if summary_file.exists():
            obj = json.loads(summary_file.read_text())
            m = obj["metrics"]
            k6_samples.append({
                "post_p95_ms": metric_value(m, "create_post_duration", "p(95)", 0.0),
                "error_rate": metric_value(m, "http_req_failed", "value", 0.0),
                "completion_p95_ms": metric_value(m, "image_completion_duration", "p(95)", None),
            })
        if processed_file.exists():
            processed_samples.append(json.loads(processed_file.read_text()))
        if dlq_file.exists():
            dlq_samples.append(json.loads(dlq_file.read_text()))

    if not k6_samples:
        continue

    post_p95_avg = safe_mean([item["post_p95_ms"] for item in k6_samples])
    error_rate_avg = safe_mean([item["error_rate"] for item in k6_samples])
    completion_p95_avg = safe_mean([item["completion_p95_ms"] for item in k6_samples])
    available_processed = [item for item in processed_samples if item.get("captureStatus") != "unavailable"]
    duplicate_side_effect_avg = safe_mean([item.get("duplicateSideEffectCount", 0) for item in available_processed])
    duplicate_ignored_avg = safe_mean([item.get("duplicateIgnoredCount", 0) for item in available_processed])
    dlq_count_avg = safe_mean([item.get("dlqApproximateMessageCount", 0) for item in dlq_samples])

    summary_lines.extend([
        f"### {scenario}",
        "",
        f"- repeats: {len(k6_samples)}",
        f"- POST /posts p95 avg(ms): {fmt(post_p95_avg)}",
        f"- API error rate avg: {fmt(error_rate_avg, 6)}",
        f"- image completion latency p95 avg(ms): {fmt(completion_p95_avg)}",
        f"- duplicate side effect count avg: {fmt(duplicate_side_effect_avg)}",
        f"- duplicate callback ignored avg: {fmt(duplicate_ignored_avg)}",
        f"- DLQ count avg: {fmt(dlq_count_avg)}",
        "",
    ])

    table_rows.append((
        scenario, len(k6_samples), post_p95_avg, error_rate_avg, completion_p95_avg,
        duplicate_side_effect_avg, dlq_count_avg
    ))

summary_lines.extend([
    "## Interpretation",
    "",
    "- `V4`는 outbox 위에 idempotent consumer와 DLQ를 추가해 중복 소비와 poison message를 격리하는 단계다.",
    "- `duplicate side effect count`는 processed jobs 저장소 기준으로 집계한다.",
    "- `DLQ count`는 보조 안정성 지표이며, 본문 비교의 1차 지표는 여전히 `POST /posts p95`, `API error rate`다.",
])

summary_path.write_text("\n".join(summary_lines).rstrip() + "\n", encoding="utf-8")

report_lines = [
    "# V4 Idempotent Baseline Report",
    "",
    "## Scope",
    "",
    "이 문서는 `exp-v4-idempotent` 기준선을 정리한다.",
    "",
    "## Aggregated Results",
    "",
    "| scenario | repeats | POST /posts p95 avg (ms) | error rate avg | image completion latency p95 avg (ms) | duplicate side effect avg | DLQ count avg |",
    "|---|---:|---:|---:|---:|---:|---:|",
]
for row in table_rows:
    report_lines.append(
        f"| {row[0]} | {row[1]} | {fmt(row[2])} | {fmt(row[3], 6)} | {fmt(row[4])} | {fmt(row[5])} | {fmt(row[6])} |"
    )
report_lines.extend([
    "",
    "## Raw Files",
    "",
    "- summary: `docs/experiments/results/exp-v4-idempotent/summary.md`",
    "- k6 summaries: `docs/experiments/results/exp-v4-idempotent/k6/*-summary.json`",
    "- metrics: `docs/experiments/results/exp-v4-idempotent/metrics/*.json`",
])
report_path.write_text("\n".join(report_lines).rstrip() + "\n", encoding="utf-8")
print(summary_path)
print(report_path)
PY
