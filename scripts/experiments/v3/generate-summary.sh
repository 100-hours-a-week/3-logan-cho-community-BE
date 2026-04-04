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
k6_dir = root / "docs/experiments/results/exp-v3-outbox/k6"
metrics_dir = root / "docs/experiments/results/exp-v3-outbox/metrics"
summary_path = root / "docs/experiments/results/exp-v3-outbox/summary.md"
report_path = root / "docs/experiments/results/exp-v3-outbox/v3-baseline-report-2026-04-05.md"

scenario_names = ["medium_10rps", "heavy_20rps", "burst_5_to_30"]

def metric_value(metrics, name, field, default=None):
    metric = metrics.get(name)
    if not metric:
        return default
    return metric.get(field, default)

def safe_mean(values):
    filtered = [value for value in values if value is not None]
    if not filtered:
        return None
    return statistics.mean(filtered)

def fmt(value, digits=2):
    if value is None:
        return "n/a"
    return f"{value:.{digits}f}"

summary_lines = [
    "# exp-v3-outbox Summary",
    "",
    "실행 일시:",
    "- 2026-04-05",
    "",
    "실행 기준:",
    "- 브랜치: `experiment/image-pipeline-evolution`",
    "- 반복: 시나리오별 3회",
    "- 1차 비교 지표: `k6` 기준 `POST /posts p95`, `API error rate`",
    "- 추가 지표: `image completion latency p95`, `orphan pending post count`, `pending outbox count`",
    "",
    "원본 결과:",
    "- `docs/experiments/results/exp-v3-outbox/k6/*-summary.json`",
    "- `docs/experiments/results/exp-v3-outbox/k6/*-stdout.log`",
    "- `docs/experiments/results/exp-v3-outbox/metrics/queue-*.json`",
    "- `docs/experiments/results/exp-v3-outbox/metrics/outbox-*.json`",
    "",
    "## Scenario Results",
    "",
]

table_rows = []
for scenario in scenario_names:
    samples = []
    outbox_samples = []
    for i in range(1, 4):
        summary_file = k6_dir / f"{scenario}-run{i}-summary.json"
        outbox_file = metrics_dir / f"outbox-{scenario}-run{i}.json"
        if summary_file.exists():
            obj = json.loads(summary_file.read_text())
            metrics = obj["metrics"]
            samples.append({
                "post_p95_ms": metric_value(metrics, "create_post_duration", "p(95)", 0.0),
                "error_rate": metric_value(metrics, "http_req_failed", "value", 0.0),
                "completion_p95_ms": metric_value(metrics, "image_completion_duration", "p(95)", 0.0),
            })
        if outbox_file.exists():
            outbox_samples.append(json.loads(outbox_file.read_text()))

    if not samples:
        continue

    post_p95s = [item["post_p95_ms"] for item in samples]
    error_rates = [item["error_rate"] for item in samples]
    completion_p95s = [item["completion_p95_ms"] for item in samples if item["completion_p95_ms"] is not None]
    available_outbox = [
        item for item in outbox_samples
        if item.get("captureStatus") != "unavailable"
    ]
    pending_outbox = [item.get("pendingOutboxCount", 0) for item in available_outbox]
    orphan_posts = [item.get("orphanPendingPostCount", 0) for item in available_outbox]
    post_p95_avg = safe_mean(post_p95s)
    error_rate_avg = safe_mean(error_rates)
    completion_p95_avg = safe_mean(completion_p95s)
    pending_outbox_avg = safe_mean(pending_outbox)
    orphan_posts_avg = safe_mean(orphan_posts)

    summary_lines.extend([
        f"### {scenario}",
        "",
        f"- repeats: {len(samples)}",
        f"- POST /posts p95 avg(ms): {fmt(post_p95_avg)}",
        f"- API error rate avg: {fmt(error_rate_avg, 6)}",
        f"- image completion latency p95 avg(ms): {fmt(completion_p95_avg)}",
        f"- outbox snapshot samples: {len(available_outbox)}",
        f"- pending outbox count avg: {fmt(pending_outbox_avg)}",
        f"- orphan pending post count avg: {fmt(orphan_posts_avg)}",
        "",
    ])

    table_rows.append(
        (
            scenario,
            len(samples),
            post_p95_avg,
            error_rate_avg,
            completion_p95_avg,
            pending_outbox_avg,
            orphan_posts_avg,
        )
    )

summary_lines.extend([
    "## Interpretation",
    "",
    "- `V3`는 direct publish 대신 outbox relay를 도입해 게시글 저장과 발행 기록을 같이 보존한다.",
    "- 본문 비교표는 여전히 `k6` 기준 응답시간과 에러율을 1차 지표로 사용한다.",
    "- outbox/queue 수치는 발행 누락과 잔여 작업을 해석하는 보조 raw 자료다.",
])

summary_path.write_text("\n".join(summary_lines).rstrip() + "\n", encoding="utf-8")

report_lines = [
    "# V3 Outbox Baseline Report",
    "",
    "## Scope",
    "",
    "이 문서는 `exp-v3-outbox` 기준선을 정리한다.",
    "",
    "## Aggregated Results",
    "",
    "| scenario | repeats | POST /posts p95 avg (ms) | error rate avg | image completion latency p95 avg (ms) | pending outbox avg | orphan pending posts avg |",
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
    "- summary: `docs/experiments/results/exp-v3-outbox/summary.md`",
    "- k6 summaries: `docs/experiments/results/exp-v3-outbox/k6/*-summary.json`",
    "- queue metrics (auxiliary raw): `docs/experiments/results/exp-v3-outbox/metrics/queue-*.json`",
    "- outbox metrics (auxiliary raw): `docs/experiments/results/exp-v3-outbox/metrics/outbox-*.json`",
    "",
    "## Notes",
    "",
    "- `V3`는 `medium_10rps` 3회, `heavy_20rps` 2회까지 수집됐다.",
    "- `burst_5_to_30`은 App EC2가 `heavy` 이후 SSH/health 응답을 잃어 아직 미수집 상태다.",
    "- `outbox-heavy_20rps-run2.json`은 부하 직후 snapshot 접속 실패로 `captureStatus=unavailable`만 남겼다.",
])

report_path.write_text("\n".join(report_lines).rstrip() + "\n", encoding="utf-8")
print(summary_path)
print(report_path)
PY
