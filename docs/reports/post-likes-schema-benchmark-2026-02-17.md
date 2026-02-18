# post_likes 최소 벤치마크 리포트 (2026-02-17)

## 목적
- 복합키 vs 단일키 구조 차이를 최소 실험으로 수치화
- `post_id` 타입 차이(`BINARY(12)` vs `VARCHAR(24)`)는 복합키에서만 검증
- 재현 가능한 고정 조건으로 결과 해석을 단순화

## 고정 조건
- `dist=skew`, `id_pattern=objectid`, `feed IN=50`
- warm-up 1회 + 측정 3회 평균
- scale: `medium` (`posts=140000`, `members=260000`, `likes=900000`)
- DB: MySQL 8.4 (Docker), `buffer_pool=48MB`, `mem_limit=384m`

## 케이스
- `A_bin`: `PK(post_id, member_id)`, `post_id BINARY(12)`
- `D2_bin`: `PK(id)`, `UNIQUE(member_id, post_id)`, `KEY(deleted_at, post_id, member_id)`, `post_id BINARY(12)`
- `A_str`: `PK(post_id, member_id)`, `post_id VARCHAR(24)`

## 결과 파일
- `test/post-likes-benchmark/results/medium_warm/summary.csv`
- `test/post-likes-benchmark/results/medium_warm/explain_A_bin.txt`
- `test/post-likes-benchmark/results/medium_warm/explain_D2_bin.txt`
- `test/post-likes-benchmark/results/medium_warm/explain_A_str.txt`
- `test/post-likes-benchmark/results/medium_warm/metadata.txt`

## 핵심 결과

| case | operation | avg_elapsed_ms | avg_bp_read_requests_delta | avg_rows_inserted_delta | data_length_mb | index_length_mb |
|---|---|---:|---:|---:|---:|---:|
| A_bin | bulk_insert | 8019.207 | 7715016.333 | 900000.000 | 44.609 | 0.000 |
| D2_bin | bulk_insert | 9070.633 | 12744914.667 | 900000.000 | 51.594 | 87.250 |
| A_str | bulk_insert | 8616.920 | 7758888.667 | 900000.000 | 56.688 | 0.000 |
| A_bin | feed_select_in50 | 1.233 | 500.000 | 0.000 | 44.609 | 0.000 |
| D2_bin | feed_select_in50 | 1.290 | 499.000 | 0.000 | 51.594 | 87.250 |
| A_str | feed_select_in50 | 2.086 | 501.000 | 0.000 | 56.688 | 0.000 |

## 해석
1. 복합키 vs 단일키 (`A_bin` vs `D2_bin`)
- 읽기(`feed_select`)는 비슷하지만, 쓰기(`bulk_insert`)는 `A_bin`이 더 빠름.
- `D2_bin`은 보조 인덱스 유지로 `bp_read_requests`가 크게 증가(약 1.65배).
- `D2_bin`은 `index_length=87.250MB`가 추가되어 write amplification이 확인됨.

2. 타입 비교 (`A_bin` vs `A_str`)
- `BINARY(12)`가 `VARCHAR(24)`보다 테이블 크기 작음 (`44.609MB` vs `56.688MB`).
- feed 쿼리도 `A_bin`이 더 빠름 (`1.233ms` vs `2.086ms`).
- 동일 복합키 구조에서 타입 차이만으로 크기/읽기 성능 차이가 재현됨.

## EXPLAIN ANALYZE 근거 요약
- `A_bin`: `PRIMARY` range scan, actual rows `337`, actual time `0.021..0.123ms`
  - `test/post-likes-benchmark/results/medium_warm/explain_A_bin.txt`
- `D2_bin`: `idx_feed_deleted_post_member` covering range scan, actual rows `337`, actual time `0.0148..0.133ms`
  - `test/post-likes-benchmark/results/medium_warm/explain_D2_bin.txt`
- `A_str`: `PRIMARY` range scan, actual rows `337`, actual time `0.0213..0.319ms`
  - `test/post-likes-benchmark/results/medium_warm/explain_A_str.txt`

## 단일키 feed 인덱스 선택 이유 (5줄)
- `idx_feed_deleted_post_member (deleted_at, post_id, member_id)` 1개만 유지했다.
- EXPLAIN에서 해당 인덱스가 `Covering index range scan`으로 사용되었다.
- 실행계획에서 `actual rows=337`로 추가 테이블 접근 없이 집계가 수행됐다.
- `member_id`를 인덱스에 포함해 `MAX(CASE WHEN member_id=?)` 계산 시 커버링을 유지했다.
- 최소 실험 목표(읽기 구조 검증)에 필요한 인덱스만 남겨 해석 복잡도를 줄였다.

## 재현 명령 (3줄)
```bash
cd test/post-likes-benchmark
SCALE=medium BUFFER_POOL_MB=48 MYSQL_MEMORY_LIMIT=384m ./run-benchmark.sh
cat results/medium_warm/summary.csv
```
