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

## ObjectId write locality benchmark

`#70` 실험은 MongoDB `ObjectId`를 RDB에 저장할 때 `VARCHAR(24)` vs `BINARY(12)` 자체보다, `timestamp` 기반 정렬 특성이 write path random I/O를 얼마나 줄이는지를 우선 검증한다.

핵심 질문:
- `ObjectId`의 시간 순서가 유지된 insert가 실제로 더 순차적인 적재를 만들었는가
- 그 효과가 `VARCHAR(24)`와 `BINARY(12)`에서 어떻게 달라지는가
- 차이의 원인이 `timestamp ordering`인지, 단순 `key width` 차이인지 구분 가능한가

비교 축:
- 표현 형식: `VARCHAR(24)` vs `BINARY(12)`
- 적재 순서: timestamp order 유지 vs shuffled order

실행:

```bash
cd test/post-likes-benchmark
ROW_COUNT=1000000 DIST_LIST="uniform" ./run-objectid-write-locality-benchmark.sh
```

secondary index 확장 비교:

```bash
cd test/post-likes-benchmark
ROW_COUNT=1000000 DIST_LIST="uniform" INDEX_MODES="base post_created" ./run-objectid-write-locality-benchmark.sh
```

주요 측정 항목:
- insert latency
- `Innodb_buffer_pool_reads`
- `Innodb_buffer_pool_read_requests`
- `Innodb_data_reads`
- `data_length`, `index_length`
- page density

결과 디렉터리:
- `results/objectid_write_locality/summary.tsv`
- `results/objectid_write_locality/insert_runs.tsv`
- `results/objectid_write_locality/*_table_stats.tsv`
- `results/objectid_write_locality/metadata.txt`

주의:
- 기존 exact lookup 중심 비교는 이번 이슈의 주 가설을 직접 검증하지 못하므로 보조 실험으로만 취급한다.
