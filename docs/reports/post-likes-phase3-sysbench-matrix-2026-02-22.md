# post_likes PK 재검증 - 3단계 매트릭스 결과 (sysbench, medium, L1/L2/L3)

## 목적
- Issue #64의 3단계를 `L1/L2/L3` 인덱스 레벨로 확장 실행해,
  PK 전략별(`C`, `S_rand`, `S_ai`) insert 중심 workload의 엔진 지표 차이를 비교한다.
- 절대 I/O 카운터와 처리량 차이가 함께 변할 때 발생하는 해석 왜곡을 방지하기 위해,
  insert 1건당 정규화 지표를 함께 본다.

## 용어 정의
- `C`:
  - 복합 PK 전략
  - `PRIMARY KEY (post_id, member_id)`
- `S_rand`:
  - 단일 PK 전략(non-monotonic)
  - `PRIMARY KEY (id BINARY(12))`
  - `idx_feed_deleted_post_member (deleted_at, post_id, member_id)` 추가
- `S_ai`:
  - 단일 PK 전략(monotonic, 대조군)
  - `PRIMARY KEY (id BIGINT AUTO_INCREMENT)`
  - `idx_feed_deleted_post_member (deleted_at, post_id, member_id)` 추가

- `L1/L2/L3`:
  - `L1`: `uk_member_post_deleted`, `idx_member`
  - `L2`: `L1 + idx_created + idx_deleted_created`
  - `L3`: `L2 + idx_post_created + idx_member_created + idx_deleted_member`

## 실행 조건 (공통)
- 스크립트: `test/post-likes-benchmark/run-phase3-sysbench.sh`
- `SCALE=medium`, `RUNS=5`, `THREADS=4`, `TIME_SECONDS=20`, `PREFILL_RATIO=0.70`
- buffer pool: `48MB`, mysql memory limit: `768m`
- 데이터:
  - `num_posts=140000`
  - `num_members=260000`
  - `num_likes=900000`
- workload event:
  - exists check 1회
  - insert(ignore) 1회

## 원본 결과 파일
- L1:
  - `test/post-likes-benchmark/results/phase3_sysbench_medium_L1/raw.tsv`
  - `test/post-likes-benchmark/results/phase3_sysbench_medium_L1/case_summary.tsv`
  - `test/post-likes-benchmark/results/phase3_sysbench_medium_L1/io_compare.tsv`
- L2:
  - `test/post-likes-benchmark/results/phase3_sysbench_medium_L2/raw.tsv`
  - `test/post-likes-benchmark/results/phase3_sysbench_medium_L2/case_summary.tsv`
  - `test/post-likes-benchmark/results/phase3_sysbench_medium_L2/io_compare.tsv`
- L3:
  - `test/post-likes-benchmark/results/phase3_sysbench_medium_L3/raw.tsv`
  - `test/post-likes-benchmark/results/phase3_sysbench_medium_L3/case_summary.tsv`
  - `test/post-likes-benchmark/results/phase3_sysbench_medium_L3/io_compare.tsv`

## 요약 테이블 (평균값)
| level | case | eps_mean | avg_ms_mean | bp_reads_mean | pages_written_mean | data_writes_mean | rows_inserted_mean |
|---|---|---:|---:|---:|---:|---:|---:|
| L1 | C | 1780.130 | 2.338 | 70066.4 | 89460.4 | 150974.0 | 35615.6 |
| L1 | S_rand | 1524.186 | 2.718 | 92628.2 | 108213.8 | 167182.2 | 30491.0 |
| L1 | S_ai | 1773.880 | 2.332 | 62720.6 | 83285.4 | 247799.2 | 35491.8 |
| L2 | C | 1281.178 | 3.126 | 49118.6 | 67569.2 | 116014.4 | 25634.4 |
| L2 | S_rand | 1193.546 | 3.418 | 72630.8 | 87909.4 | 134886.6 | 23893.0 |
| L2 | S_ai | 1117.140 | 3.660 | 37660.2 | 57807.2 | 100283.2 | 22350.0 |
| L3 | C | 1121.940 | 3.628 | 110479.8 | 124848.4 | 171735.4 | 22455.6 |
| L3 | S_rand | 859.640 | 4.676 | 107341.0 | 114737.6 | 150878.8 | 17201.4 |
| L3 | S_ai | 1165.130 | 3.616 | 116038.2 | 125322.8 | 172988.0 | 23312.4 |

## C 대비 비교 (정규화 지표 포함)
아래 값은 C 대비 상대 변화율이다.

### L1
- `S_rand`:
  - `eps -14.38%`, `avg_latency +16.25%`
  - `bp_reads_per_insert +54.42%`
  - `pages_written_per_insert +41.29%`
  - `data_writes_per_insert +29.35%`
- `S_ai`:
  - `eps -0.35%`, `avg_latency -0.26%`
  - `bp_reads_per_insert -10.17%`
  - `pages_written_per_insert -6.58%`
  - `data_writes_per_insert +64.71%` (쓰기 경로 악화 신호)

### L2
- `S_rand`:
  - `eps -6.84%`, `avg_latency +9.34%`
  - `bp_reads_per_insert +58.65%`
  - `pages_written_per_insert +39.59%`
  - `data_writes_per_insert +24.74%`
- `S_ai`:
  - `eps -12.80%`, `avg_latency +17.08%`
  - `bp_reads_per_insert -12.06%`
  - `pages_written_per_insert -1.88%`
  - `data_writes_per_insert -0.86%`

### L3
- `S_rand`:
  - `eps -23.38%`, `avg_latency +28.89%`
  - `bp_reads_per_insert +26.84%`
  - `pages_written_per_insert +19.97%`
  - `data_writes_per_insert +14.69%`
- `S_ai`:
  - `eps +3.85%`, `avg_latency -0.33%`
  - `bp_reads_per_insert +1.17%`
  - `pages_written_per_insert -3.31%`
  - `data_writes_per_insert -2.97%`

## 엔지니어링 해석
1. `S_rand`는 L1/L2/L3 전 구간에서 정규화 I/O와 성능이 일관되게 악화한다.
- 즉 non-monotonic 단일 PK는 본 조건에서 random I/O 완화 전략으로 유효하지 않다.

2. `S_ai`는 레벨에 따라 결과가 갈린다.
- L1: throughput은 C와 유사하나 `data_writes_per_insert`가 크게 증가.
- L2: 읽기 I/O는 개선되지만 throughput/latency는 악화.
- L3: throughput은 C를 소폭 상회하고 latency도 유사, 정규화 I/O는 거의 비슷하거나 일부만 개선.

3. 절대 카운터만 보면 오판 가능성이 있다.
- 예: L3 `S_rand`는 절대 read 카운터만 보면 C보다 약간 낮아 보이지만,
  이는 처리량(삽입 row 수) 자체가 크게 줄어든 영향이다.
- 따라서 전략 비교는 반드시 `per_insert` 정규화 지표와 함께 해석해야 한다.

## 오차/한계
- `runs=5` 기준 변동성이 여전히 크다.
  - 예: `S_ai/L3` `avg_ms_cv=24.641%`
- sysbench percentile(`95th percentile`)이 `0.00`으로 출력되는 현상이 있어,
  p95/p99 기반 비교는 현재 보류했다.
- 따라서 현재 결론은 mean/CV/CI95 + InnoDB status counter 중심의 중간 판단이다.

## 중간 결론
- 단일 PK 전략의 효과는 "단일 여부"가 아니라 "PK 생성 패턴(monotonic 여부)"에 의해 크게 좌우된다.
- `S_rand`는 채택 근거가 약하고, `S_ai`는 레벨/지표에 따라 장단이 혼재한다.
- 운영 적용 판단을 위해서는:
  1) percentile 계측 보강
  2) run 수 확대(신뢰구간 축소)
  3) 쓰기 경로(`data_writes_per_insert`) 이상치 원인 분해
  가 추가로 필요하다.
