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
k6_dir = root / "docs/experiments/results/exp-v1-sync/k6"
metrics_dir = root / "docs/experiments/results/exp-v1-sync/metrics"
summary_path = root / "docs/experiments/results/exp-v1-sync/summary.md"

scenario_names = ["medium_10rps", "heavy_20rps", "burst_5_to_30"]

def p95_from_summary(path):
    obj = json.loads(path.read_text())
    metrics = obj["metrics"]
    return {
        "post_p95_ms": metrics["create_post_duration"]["p(95)"],
        "error_rate": metrics["http_req_failed"]["value"],
    }

def cpu_stats(path):
    cpu_values = []
    mem_values = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("Linux") or line.startswith("Average:") or line.startswith("UID"):
            continue
        parts = line.split()
        if len(parts) < 8:
            continue
        try:
            cpu = float(parts[-2])
            mem = float(parts[-1])
        except ValueError:
            continue
        cpu_values.append(cpu)
        mem_values.append(mem)
    if not cpu_values:
        return None
    return {
        "cpu_avg": statistics.mean(cpu_values),
        "cpu_max": max(cpu_values),
        "mem_avg": statistics.mean(mem_values) if mem_values else 0.0,
    }

lines = ["# exp-v1-sync Summary", "", "## Scenario Results", ""]

for scenario in scenario_names:
    samples = []
    cpu_samples = []
    for i in range(1, 4):
        summary_file = k6_dir / f"{scenario}-run{i}-summary.json"
        cpu_file = metrics_dir / f"cpu-{scenario}-run{i}.log"
        if not summary_file.exists():
            continue
        samples.append(p95_from_summary(summary_file))
        if cpu_file.exists():
            stat = cpu_stats(cpu_file)
            if stat:
                cpu_samples.append(stat)

    if not samples:
        continue

    post_p95s = [s["post_p95_ms"] for s in samples]
    error_rates = [s["error_rate"] for s in samples]
    lines.extend([
        f"### {scenario}",
        "",
        f"- repeats: {len(samples)}",
        f"- POST /posts p95 avg(ms): {statistics.mean(post_p95s):.2f}",
        f"- POST /posts p95 min(ms): {min(post_p95s):.2f}",
        f"- POST /posts p95 max(ms): {max(post_p95s):.2f}",
        f"- API error rate avg: {statistics.mean(error_rates):.6f}",
    ])
    if cpu_samples:
        cpu_avg = statistics.mean(item["cpu_avg"] for item in cpu_samples)
        cpu_max = max(item["cpu_max"] for item in cpu_samples)
        lines.append(f"- Spring CPU avg(%usr+%system): {cpu_avg:.2f}")
        lines.append(f"- Spring CPU max(%usr+%system): {cpu_max:.2f}")
    lines.append("")

summary_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
print(summary_path)
PY
