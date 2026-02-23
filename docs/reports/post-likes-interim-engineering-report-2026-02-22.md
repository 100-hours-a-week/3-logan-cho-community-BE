# post_likes PK 재검증 중간 엔지니어링 리포트 (Issue #64)

> 참고: 이 문서는 실행 로그 중심의 중간본이다.  
> 이슈 #64의 가설 검증 흐름(가설1~4, A/B/C 판정)에 맞춘 기준 문서는
> `docs/reports/post-likes-hypothesis-validation-report-2026-02-23.md` 이다.

## 0) 범위와 상태
- 본 문서는 Issue #64의 1~3단계 중 현재 완료된 단위를 기준으로 작성한 중간 보고다.
- 완료:
  - 1단계 covering 선검증 (`phase1_covering_medium`)
  - 2단계 인덱스 구조/공간/임계점 (`phase2_index_size_medium`)
  - 3단계 sysbench 랜덤 I/O 실측 (`phase3_sysbench_medium_L1/L2/L3`, 각 5 runs)
- 미완료:
  - percentile 계측 정밀화(현재 sysbench 출력 한계 존재)

---

## 1) 실험 환경 요약
- 데이터 스케일: `medium`
  - `num_posts=140000`
  - `num_members=260000`
  - `num_likes=900000`
- 엔진/리소스:
  - MySQL 8.4 (docker)
  - `innodb_buffer_pool_size=48MB` (working set 대비 작게 유지해 랜덤 I/O 유도)
  - container memory `768m`
- ID/분포:
  - `post_id=BINARY(12)` (Mongo ObjectId 유사 고정 길이)
  - post 분포: skew(핫포스트 집중)
- 케이스:
  - `C`: `PK(post_id, member_id)` (복합 PK)
  - `S_rand`: `PK(id BINARY(12) non-monotonic)` + feed 보조인덱스
  - `S_ai`: `PK(id BIGINT AUTO_INCREMENT)` + feed 보조인덱스

---

## 2) 수치가 의미하는 측정 행위
- `events_per_sec`:
  - sysbench `transactions/sec`
  - 1 event = `exists check` 1회 + `INSERT IGNORE ... SELECT` 1회
- `avg_latency_ms`:
  - event 1회의 평균 지연
- `innodb_buffer_pool_reads_delta`:
  - buffer pool miss로 디스크에서 page를 읽은 횟수 증가량
- `innodb_data_reads_delta`:
  - InnoDB 데이터 read I/O 호출량 증가
- `innodb_pages_written_delta`:
  - dirty page flush 등 페이지 쓰기 증가량
- `innodb_data_writes_delta`:
  - InnoDB 데이터 write I/O 호출량 증가
- `innodb_rows_inserted_delta`:
  - run 구간에서 insert 처리된 row 증가량

즉, 3단계 수치는 "동일 시간(20s) 동안 해당 insert 중심 workload를 수행할 때 발생한 처리량/지연/엔진 I/O 카운터 변화량"이다.

---

## 3) 1단계 결과 해석 (covering 여부)
출처: `test/post-likes-benchmark/results/phase1_covering_medium/summary.tsv`

핵심 결과:
1. feed aggregate 쿼리는 `C/S_rand/S_ai` 모두 `idx_feed_deleted_post_member`로 covering 성립.
2. exists check는 `S_rand/S_ai`는 covering(`uk_member_post_deleted`), `C`는 `PRIMARY` 접근으로 non-covering.
3. bulk update path는 3케이스 공통 `Using where; Using temporary`.

의미:
- "조회가 어느 전략에서만 성립/불성립"하는 문제가 아님.
- 최종 의사결정의 중심은 조회 미세 차이보다 2~3단계의 구조적 비용(인덱스 공간, 랜덤 I/O)이어야 함.

---

## 4) 2단계 결과 해석 (공간/임계점)
출처:
- `test/post-likes-benchmark/results/phase2_index_size_medium/summary.tsv`
- `test/post-likes-benchmark/results/phase2_index_size_medium/break_even.tsv`

### 4-1) L3 기준 구조 차이
- `C`:
  - `primary_mb=71.656`
  - `common_secondary_mb=271.312`
- `S_rand`:
  - `primary_mb=88.641` (`C` 대비 +23.7%)
  - `common_secondary_mb=285.438` (`C` 대비 +5.21%)
  - `extra_single_mb=58.750`
- `S_ai`:
  - `primary_mb=51.594` (`C` 대비 -28.0%)
  - `common_secondary_mb=252.203` (`C` 대비 -7.04%)
  - `extra_single_mb=51.641`

### 4-2) break-even
- `S_ai`:
  - `L2~L3`에서 `break_even_k ≈ 18~19`
  - 현재 src 유사 공통 인덱스 수(`4~7개`)로는 상쇄 전 구간
- `S_rand`:
  - 공통 보조인덱스 절감이 음수(오히려 증가)라 `break_even=inf`

의미:
1. "단일 PK면 무조건 보조인덱스가 작다"는 명제는 성립하지 않음.
2. 단일 PK의 이점은 PK가 monotonic(`S_ai`)일 때만 부분적으로 확인됨.
3. non-monotonic PK(`S_rand`)는 클러스터드/보조 모두에서 공간 페널티가 생길 수 있음.

---

## 5) 3단계 결과 해석 (sysbench)
출처:
- `docs/reports/post-likes-phase3-sysbench-matrix-2026-02-22.md`

### 5-1) 워크로드 구성 (공통)
- prefill: 전체 90만 중 63만(70%) 선적재
- 측정 런: 남은 source window를 run별 분할
- run 설정: `threads=4`, `time=20s`, `runs=5` (레벨별 동일)
- 각 event:
  - exists check 1회
  - insert(ignore) 1회

### 5-2) 대표 결과(L2, 5 runs)
| case | eps_mean | avg_ms_mean | bp_reads_mean | data_reads_mean | pages_written_mean | data_writes_mean | rows_inserted_mean |
|---|---:|---:|---:|---:|---:|---:|---:|
| C | 1281.178 | 3.126 | 49118.6 | 49119.6 | 67569.2 | 116014.4 | 25634.4 |
| S_rand | 1193.546 | 3.418 | 72630.8 | 72633.8 | 87909.4 | 134886.6 | 23893.0 |
| S_ai | 1117.140 | 3.660 | 37660.2 | 37660.2 | 57807.2 | 100283.2 | 22350.0 |

### 5-3) C 대비 변화율
- `S_rand`:
  - 처리량 `-6.84%`
  - 평균 지연 `+9.34%`
  - buffer_pool_reads `+47.87%`
  - data_reads `+47.87%`
  - pages_written `+30.10%`
  - data_writes `+16.27%`
- `S_ai`:
  - 처리량 `-12.80%`
  - 평균 지연 `+17.08%`
  - buffer_pool_reads `-23.33%`
  - data_reads `-23.33%`
  - pages_written `-14.45%`
  - data_writes `-13.56%`

### 5-4) insert 1건당 I/O 효율(평균)
- `C`:
  - `bp_reads/inserted_row = 1.9161`
- `S_rand`:
  - `bp_reads/inserted_row = 3.0398` (`C` 대비 악화)
- `S_ai`:
  - `bp_reads/inserted_row = 1.6850` (`C` 대비 개선)

의미:
1. `S_rand`는 처리량/지연/I/O 모두 악화. non-monotonic PK가 랜덤 I/O를 줄이지 못하고 오히려 늘림.
2. `S_ai`는 I/O 카운터는 개선됐지만 처리량/지연은 악화. 즉 I/O 절감이 곧 TPS 개선으로 직결되지는 않음.
3. 3단계 결과는 "random I/O를 없애는가"보다 "어느 인덱스/경로로 이동시키고, 그 이동이 throughput에 어떤 2차 비용을 만드는가"를 분리해서 봐야 함을 보여줌.
4. 전체 L1/L2/L3 매트릭스 기준 해석은 별도 문서(`post-likes-phase3-sysbench-matrix-2026-02-22.md`)를 따른다.

---

## 6) 오차/신뢰도/한계
### 6-1) 변동성(CV, 5 runs)
- `C`:
  - `eps_cv=4.71%`, `avg_latency_cv=4.91%`
- `S_rand`:
  - `eps_cv=16.98%`, `avg_latency_cv=14.95%`
- `S_ai`:
  - `eps_cv=16.22%`, `avg_latency_cv=17.30%`

해석:
- `S_rand/S_ai`는 run-to-run 변동성이 커서 평균만으로 단정하기 어렵다.
- 특히 `S_rand` run5(고처리량) 같은 outlier가 평균에 영향.

### 6-2) 신뢰구간(95% CI, 평균 latency)
- `C`: `3.126 ± 0.135ms`
- `S_rand`: `3.418 ± 0.448ms`
- `S_ai`: `3.660 ± 0.555ms`

해석:
- 구간 일부가 겹치므로 "latency 우열"은 추가 반복(예: runs>=10) 후 재확인이 안전.

### 6-3) 계측 한계
- sysbench 1.0.20 + 본 Lua workload에서 `95th percentile`이 `0.00`으로 출력되는 현상 확인.
- 따라서 현재 p95/p99는 유효한 percentile 근거로 사용하지 않았고, mean/CV/CI95 + 엔진 I/O 지표를 중심으로 해석.

---

## 7) Issue #64 가설 대비 중간 결론
1. 가설1/가설3 (보조인덱스 leaf 밀도/인덱스 수 증가 누적 효과):
   - `S_ai`에서만 부분적으로 지지.
   - `S_rand`에서는 반례 관측.
2. 가설2 (leaf 밀도 증가 -> 랜덤 I/O 완화):
   - `S_ai`는 완화 신호 존재(읽기/쓰기 I/O 감소).
   - `S_rand`는 반대로 악화.
3. 가설4 (랜덤 I/O 제거가 아니라 위치 이동):
   - 지지됨.
   - 단, 이동 결과는 PK 생성 패턴(monotonic vs non-monotonic)에 따라 완전히 달라짐.

중간 판단:
- 현재 데이터만으로는 "단일 PK 일반 채택" 근거는 부족.
- 만약 단일 PK를 검토한다면 `S_ai`처럼 monotonic clustering 기반으로 별도 검증을 계속해야 하며,
  `S_rand`와 동일시하면 잘못된 결론 가능성이 높음.

---

## 8) 남은 작업(이 PR 이후 계속)
1. `runs` 확대(예: 10~15)로 CI 폭 축소.
2. percentile 계측 보강(대안 계측 도입 또는 sysbench 버전/옵션 교체) 후 p95/p99 재수집.
3. `data_writes_per_insert` 이상치 구간(L1/S_ai) 원인 분해.
4. 최종 리포트에서 운영 적용 권고안(복합 PK 유지 vs 단일 PK 전환 조건)을 명시.
