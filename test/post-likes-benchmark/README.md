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
