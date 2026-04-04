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
k6_dir = root / "docs/experiments/results/exp-v2-async/k6"
metrics_dir = root / "docs/experiments/results/exp-v2-async/metrics"
summary_path = root / "docs/experiments/results/exp-v2-async/summary.md"
report_path = root / "docs/experiments/results/exp-v2-async/v2-baseline-report-2026-04-04.md"

scenario_names = ["medium_10rps", "heavy_20rps", "burst_5_to_30"]

def metric_value(metrics, name, field, default=None):
    metric = metrics.get(name)
    if not metric:
        return default
    return metric.get(field, default)

summary_lines = [
    "# exp-v2-async Summary",
    "",
    "실행 일시:",
    "- 2026-04-04",
    "",
    "실행 기준:",
    "- 브랜치: `experiment/image-pipeline-evolution`",
    "- 반복: 시나리오별 3회",
    "- 1차 비교 지표: `k6` 기준 `POST /posts p95`, `API error rate`",
    "- 추가 지표: `image completion latency p95`",
    "",
    "원본 결과:",
    "- `docs/experiments/results/exp-v2-async/k6/*-summary.json`",
    "- `docs/experiments/results/exp-v2-async/k6/*-stdout.log`",
    "- `docs/experiments/results/exp-v2-async/metrics/queue-*.json`",
    "",
    "## Scenario Results",
    "",
]

table_rows = []
for scenario in scenario_names:
    samples = []
    queue_samples = []
    for i in range(1, 4):
        summary_file = k6_dir / f"{scenario}-run{i}-summary.json"
        queue_file = metrics_dir / f"queue-{scenario}-run{i}.json"
        if summary_file.exists():
            obj = json.loads(summary_file.read_text())
            metrics = obj["metrics"]
            samples.append({
                "post_p95_ms": metric_value(metrics, "create_post_duration", "p(95)", 0.0),
                "error_rate": metric_value(metrics, "http_req_failed", "value", 0.0),
                "completion_p95_ms": metric_value(metrics, "image_completion_duration", "p(95)", 0.0),
            })
        if queue_file.exists():
            queue_samples.append(json.loads(queue_file.read_text()))

    if not samples:
        continue

    post_p95s = [item["post_p95_ms"] for item in samples]
    error_rates = [item["error_rate"] for item in samples]
    completion_p95s = [item["completion_p95_ms"] for item in samples]
    summary_lines.extend([
        f"### {scenario}",
        "",
        f"- repeats: {len(samples)}",
        f"- POST /posts p95 avg(ms): {statistics.mean(post_p95s):.2f}",
        f"- API error rate avg: {statistics.mean(error_rates):.6f}",
        f"- image completion latency p95 avg(ms): {statistics.mean(completion_p95s):.2f}",
        "",
    ])

    table_rows.append(
        (
            scenario,
            len(samples),
            statistics.mean(post_p95s),
            statistics.mean(error_rates),
            statistics.mean(completion_p95s),
        )
    )

summary_lines.extend([
    "## Interpretation",
    "",
    "- `V2`는 이미지 처리를 요청 경로에서 제거해 `POST /posts` 기준 응답시간을 `V1`보다 낮추는 것이 목표다.",
    "- 이미지 완료까지의 지연은 `image completion latency`로 별도 추적한다.",
    "- `queue-*.json`은 보조 진단용 raw 자료로만 남기고, 본문 비교표의 1차 수치로 사용하지 않는다.",
])

summary_path.write_text("\n".join(summary_lines).rstrip() + "\n", encoding="utf-8")

report_lines = [
    "# V2 Async Baseline Report",
    "",
    "## Scope",
    "",
    "이 문서는 `exp-v2-async` 기준선을 정리한다.",
    "",
    "## Aggregated Results",
    "",
    "| scenario | repeats | POST /posts p95 avg (ms) | error rate avg | image completion latency p95 avg (ms) |",
    "|---|---:|---:|---:|---:|",
]

for row in table_rows:
    report_lines.append(
        f"| {row[0]} | {row[1]} | {row[2]:.2f} | {row[3]:.6f} | {row[4]:.2f} |"
    )

report_lines.extend([
    "",
    "## Raw Files",
    "",
    "- summary: `docs/experiments/results/exp-v2-async/summary.md`",
    "- k6 summaries: `docs/experiments/results/exp-v2-async/k6/*-summary.json`",
    "- queue metrics (auxiliary raw): `docs/experiments/results/exp-v2-async/metrics/queue-*.json`",
])

report_path.write_text("\n".join(report_lines).rstrip() + "\n", encoding="utf-8")
print(summary_path)
print(report_path)
PY
