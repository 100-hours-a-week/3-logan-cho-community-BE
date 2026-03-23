# post_likes 최소 벤치마크

이 벤치는 아래 3개 케이스만 비교한다.
- `A_bin`: `PK(post_id, member_id)`, `post_id BINARY(12)`
- `D2_bin`: `PK(id)`, `UNIQUE(member_id, post_id)`, `KEY(deleted_at, post_id, member_id)`, `post_id BINARY(12)`
- `A_str`: `PK(post_id, member_id)`, `post_id VARCHAR(24)`

고정 조건:
- `dist=skew`
- `id_pattern=objectid`
- `feed IN size=50`
- warm-up 1회 후 3회 평균
- 측정 작업: `bulk INSERT`, `feed SELECT`

## 실행 (3줄)

```bash
cd test/post-likes-benchmark
SCALE=medium BUFFER_POOL_MB=48 MYSQL_MEMORY_LIMIT=384m ./run-benchmark.sh
cat results/medium_warm/summary.csv
```

## 결과 파일

`results/medium_warm/`에 고정 생성:
- `summary.csv`
- `metadata.txt`
- `explain_A_bin.txt`
- `explain_D2_bin.txt`
- `explain_A_str.txt`

## 측정 지표

- `elapsed_ms`
- `Innodb_buffer_pool_read_requests` delta
- `Innodb_rows_inserted` delta
- `EXPLAIN ANALYZE` (사용 인덱스, actual rows/time)
- `information_schema.tables` (`data_length`, `index_length`)

## PK 순수 비교

`#67` 실험은 soft delete/feed covering을 제외하고 `12B post_id` 기준으로 아래 두 케이스만 비교한다.
- `C`: `PRIMARY KEY (post_id, member_id)`
- `S`: `PRIMARY KEY (post_like_id)`, `UNIQUE KEY uk_post_member (post_id, member_id)`

실행:

```bash
cd test/post-likes-benchmark
ROW_COUNT=1000000 DIST_LIST="uniform skew" ./run-pk-pure-baseline.sh
```

결과 디렉터리:
- `results/pk_pure_baseline_12b/summary.tsv`
- `results/pk_pure_baseline_12b/lookup_probe.tsv`
- `results/pk_pure_baseline_12b/*_table_stats.tsv`

## Break-even 재측정

`#68` 실험은 `12B post_id` 고정 기준에서 공통 secondary 개수와 데이터 양을 늘리며 손익분기점을 계산한다.

실행:

```bash
cd test/post-likes-benchmark
ROW_COUNTS="100000 300000 1000000" LEVELS="L0 L1 L2 L3 L4 L5" DIST_LIST="uniform skew" ./run-pk-break-even.sh
```

결과 디렉터리:
- `results/pk_break_even_12b/size_matrix.tsv`
- `results/pk_break_even_12b/density_matrix.tsv`
- `results/pk_break_even_12b/io_matrix.tsv`
- `results/pk_break_even_12b/break_even_by_secondary.tsv`
- `results/pk_break_even_12b/break_even_by_row_count.tsv`
