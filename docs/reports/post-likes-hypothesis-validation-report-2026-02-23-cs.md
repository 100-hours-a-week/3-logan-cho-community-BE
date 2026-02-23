# [DB-ENGINE] post_likes PK 검증 결과 보고 (C vs S, fixed-events)

## 1. 목적
Issue #64의 목적대로 `post_likes` PK 전략을 엔진 레벨에서 검증했다.

- 비교축:
  - `C`: `PK(post_id, member_id)` (복합 PK)
  - `S`: `PK(id BIGINT AUTO_INCREMENT)` (단일 PK, monotonic)
- 제외:
  - 랜덤 단일 PK(`S_rand`)는 운영 후보가 아니므로 본 검증에서 제외

핵심 질문:
1. src 문제 쿼리가 실제 covering으로 동작하는가?
2. 인덱스 크기/leaf 밀집도 차이가 어느 수준인가?
3. 그 차이가 random I/O 완화로 연결되는가?
4. 보조 인덱스 수 증가 시 break-even이 존재하는가?

---

## 2. 이전 실험의 결함과 보정
이전 해석 혼선의 핵심 원인은 `fixed-time` 실행으로 케이스별 작업량이 달랐던 점이었다.

이번 실험에서는 다음을 강제했다.
1. `fixed-events`로 실행 (`events_per_run=54000`, run당 동일 작업량)
2. run window 동일 (`sid` 구간 동일)
3. 케이스별 데이터셋 재초기화 후 실행 (`init_dataset` per case)
4. 절대 I/O + per-insert 정규화 지표 동시 기록

즉, 이번 수치는 `C/S` 간 작업량 불일치가 아닌 구조 차이를 비교하도록 설계했다.

---

## 3. 실험 환경 요약
- scale: `medium` (`posts=140000`, `members=260000`, `likes=900000`)
- buffer pool: `48MB`
- DB: MySQL 8.4 (InnoDB)
- 분포: skew
- 단계:
  - phase1: covering 검증
  - phase2: index size + density + break-even
  - phase3: sysbench random I/O (`L1/L2/L3`, 각 `runs=5`)

---

## 4. 1단계 결과 (covering)
출처: `test/post-likes-benchmark/results/phase1_covering_medium_cs/summary.tsv`

| query | C | S |
|---|---|---|
| feed_aggregate | `idx_feed_deleted_post_member`, `Using index=yes` | `idx_feed_deleted_post_member`, `Using index=yes` |
| exists_check | `PRIMARY`, `Using index=no` | `idx_feed_deleted_post_member`, `Using index=yes` |
| bulk_update_path | `uk_member_post_deleted`, `Using temporary` | `uk_member_post_deleted`, `Using temporary` |

요약:
- feed는 `C/S` 모두 covering 성립.
- exists는 `S`가 covering 경로.
- 조회 성능 자체보다 이후 구조/쓰기 비용 비교가 핵심.

---

## 5. 2단계 결과 (공간 + leaf 밀집도 + break-even)
출처:
- `test/post-likes-benchmark/results/phase2_index_size_medium_cs/summary.tsv`
- `test/post-likes-benchmark/results/phase2_index_size_medium_cs/density_summary.tsv`
- `test/post-likes-benchmark/results/phase2_index_size_medium_cs/break_even.tsv`

## 5-1. 공간
L2/L3 기준:
- `primary_mb`: `C=71.656`, `S=51.594` (`S`가 **-28.0%**)
- `common_secondary_mb`:
  - `L2`: `C=136.421`, `S=124.343` (**-8.85%**)
  - `L3`: `C=271.312`, `S=252.203` (**-7.04%**)
- `S`는 feed 추가 인덱스 `idx_feed_deleted_post_member`를 **+51.641MB** 보유

## 5-2. rows_per_leaf_page 밀집도
- Primary rows/page:
  - `C=227.330`, `S=273.889` (`S` **+20.48%**)
- Common secondary rows/page:
  - `L2`: `C=453.401`, `S=503.004` (`S` **+10.94%**)
  - `L3`: `C=409.304`, `S=443.975` (`S` **+8.47%**)

## 5-3. break-even
- `L2`: `break_even_k=18`, 현재 `k=4` -> 미도달
- `L3`: `break_even_k=19`, 현재 `k=7` -> 미도달
- `L1`: 공통 절감량 음수 -> `inf`

요약:
- `S`는 primary/공통 secondary 밀집도에서 우세 신호가 있지만,
- 현재 인덱스 개수(4~7)에서는 feed 추가 인덱스 비용 상쇄 전 구간이다.

---

## 6. 3단계 결과 (random I/O, fixed-events)
출처:
- `test/post-likes-benchmark/results/phase3_sysbench_medium_L1_cs/case_summary.tsv`
- `test/post-likes-benchmark/results/phase3_sysbench_medium_L2_cs/case_summary.tsv`
- `test/post-likes-benchmark/results/phase3_sysbench_medium_L3_cs/case_summary.tsv`
- 각 level의 `io_compare.tsv`

## 6-1. random I/O 완화율 (C 대비)
`io_reduction_rate = (C - S) / C`

- L1:
  - buffer_pool_reads: **+7.565%**
  - data_reads: **+7.567%**
  - pages_written: **+8.196%**
  - data_writes: **+6.064%**
- L2:
  - buffer_pool_reads: **+6.516%**
  - data_reads: **+6.518%**
  - pages_written: **+7.698%**
  - data_writes: **+4.630%**
- L3:
  - buffer_pool_reads: **-2.402%** (악화)
  - data_reads: **-2.399%** (악화)
  - pages_written: **+0.271%**
  - data_writes: **+0.471%**

## 6-2. 성능 신호 (eps/latency)
- L1: `S`가 `eps +29.31%`, `avg_latency -21.22%`
- L2: `S`가 `eps +32.10%`, `avg_latency -20.96%`
- L3: `S`가 `eps -11.83%`, `avg_latency +12.83%`

요약:
- L1/L2에서는 `S`가 read/write 모두 개선 신호.
- L3에서는 read 완화가 사라지고(`-2.4%`) 성능도 역전.

---

## 7. 가설 판정 (Issue #64)
1. 가설1(보조 index PK 축소 -> 밀집도 증가): **지지**
   - L2/L3 common secondary rows/page 증가(+10.94%, +8.47%)
2. 가설2(클러스터드 밀집도는 단일PK에서 감소 가능): **반례 관측**
   - 본 조건에서는 오히려 `S`가 primary rows/page +20.48%
3. 가설3(밀집도 증가 -> random I/O 감소): **조건부 지지**
   - L1/L2 지지, L3에서는 소멸/역전
4. 가설4(인덱스 수 증가 시 누적 + break-even): **지지**
   - break-even `k=18~19` 존재, 현재 `k=4~7` 미도달
5. 가설5(I/O 제거가 아닌 위치 이동): **지지**
   - L3에서 read 이득 소멸, 레벨별 신호가 달라짐

---

## 8. 최종 판단 (A/B/C)
- A(단일 PK 채택): **보류**
  - L1/L2는 유리하나 L3에서 역전
  - 현재 인덱스 수 구간에서 break-even 미도달
- B(복합 PK 유지): **현시점 운영 판단 채택**
  - 구조적 역전 근거가 아직 불충분
- C(auto_increment에서만 개선): **참고 채택**
  - 본 실험 축 자체가 monotonic 단일 PK 기준

현재 권고:
- 운영은 `B`(복합 PK 유지)를 기본으로 두고,
- 단일 PK 전환은 인덱스 구성과 워크로드 레벨(`L3` 유사)에서 추가 검증 후 판단.

---

## 9. 남은 검증
1. percentile 신뢰성 보강 (p95/p99 개선)
2. run 확대(>=10)로 CI 축소
3. L3 역전 원인(인덱스 fan-out + maintenance cost) 추가 분해
