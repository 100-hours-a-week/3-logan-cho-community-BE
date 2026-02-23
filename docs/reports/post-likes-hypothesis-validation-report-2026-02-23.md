# [DB-ENGINE] post_likes PK 전략 재검증 결과 보고 (Issue #64)

## 1. 목적
본 보고서는 Issue #64의 핵심 질문을 검증하기 위한 결과 보고다.

검증 질문:
1. 실제 `src` 쿼리는 전략별로 covering 인덱스로 동작하는가?
2. 복합 PK 클러스터드 인덱스 vs 단일 PK 보조 인덱스의 공간 차이는 실제로 몇 %인가?
3. 그 공간 차이가 랜덤 I/O 완화로 이어지는가?
4. 보조 인덱스 수가 증가할수록 단일 PK가 역전하는 임계점이 존재하는가?

핵심은 "어느 쪽이 빠른가"가 아니라, "어느 구조가 장기적으로 확장성 있는가"다.

---

## 2. 가설
Issue #64의 사전 가설을 그대로 기준으로 검증했다.

- 가설 1: 보조 인덱스에서 PK 길이 감소는 leaf 밀도 증가로 이어진다.
- 가설 2: leaf 밀도 증가는 랜덤 I/O 확률을 줄인다.
- 가설 3: 보조 인덱스 수 증가 시 PK 길이 차이는 선형 누적되며 break-even이 존재한다.
- 가설 4: 단일 PK는 랜덤 I/O를 제거하는 것이 아니라 위치를 이동시킨다.

---

## 3. 검증 설계 요약
### 3-1. 공통 전제
- `post_id=BINARY(12)` 고정(Mongo ObjectId 가정)
- `SCALE=medium`: post 140k, member 260k, likes 900k
- `innodb_buffer_pool_size=48MB`로 랜덤 I/O 유발 조건 유지

### 3-2. 스키마 매트릭스
- `C`: `PK(post_id, member_id)` (복합 PK)
- `S_rand`: `PK(id BINARY(12), non-monotonic)` + 동일 보조 인덱스
- `S_ai`: `PK(id BIGINT AUTO_INCREMENT)` + 동일 보조 인덱스 (대조군)

### 3-3. 단계별 검증
- 1단계: covering 선검증 (`phase1_covering_medium`)
- 2단계: 인덱스 구조/공간/임계점 (`phase2_index_size_medium`)
- 3단계: sysbench 엔진 레벨 실측 (`phase3_sysbench_medium_L1/L2/L3`, 각 runs=5)

상세 raw/스크립트는 다음 문서를 참조:
- `docs/reports/post-likes-phase1-covering-2026-02-22.md`
- `docs/reports/post-likes-phase2-index-size-2026-02-22.md`
- `docs/reports/post-likes-phase3-sysbench-matrix-2026-02-22.md`

---

## 4. 가설별 검증 결과
## 4-1. 가설 1 검증: "PK 길이 감소 -> 보조 인덱스 leaf 밀도 증가"
관측 지표: `common_secondary_mb` (공통 보조 인덱스 총합)

### 결과
- `L2`:
  - `C=136.421MB`
  - `S_ai=124.343MB` (`-8.85%`)
  - `S_rand=144.516MB` (`+5.93%`)
- `L3`:
  - `C=271.312MB`
  - `S_ai=252.203MB` (`-7.04%`)
  - `S_rand=285.438MB` (`+5.21%`)

### 판정
- `S_ai` 기준: 가설 1 지지(보조 인덱스 공간 절감 확인).
- `S_rand` 기준: 가설 1 반례(공간 증가).

즉, "단일 PK" 자체보다 "PK의 monotonic 특성"이 결과를 좌우한다.

---

## 4-2. 가설 2 검증: "leaf 밀도 증가 -> 랜덤 I/O 완화"
관측 지표: `buffer_pool_reads_per_insert` (insert 1건당 read miss 정규화)

### 결과 (C 대비)
- `L1`:
  - `S_ai: -10.17%` (완화)
  - `S_rand: +54.42%` (악화)
- `L2`:
  - `S_ai: -12.06%` (완화)
  - `S_rand: +58.65%` (악화)
- `L3`:
  - `S_ai: +1.17%` (완화 소멸/유사)
  - `S_rand: +26.84%` (악화)

### 판정
- `S_ai`에서 L1/L2 조건부 지지.
- L3에서는 완화 효과가 소멸.
- `S_rand`는 전 구간 반례.

가설 2는 "항상 참"이 아니라, monotonic PK + 특정 인덱스/작업부하 조건에서만 부분 성립한다.

---

## 4-3. 가설 3 검증: "인덱스 수 증가 시 누적 + break-even 존재"
관측 지표: `break_even.tsv`

### 결과
- `S_ai`:
  - `extra_single_cost=51.641MB`
  - `break_even_k≈18(L2), 19(L3)`
- `S_rand`:
  - 절감량이 음수라 `break_even=inf`

현재 `src` 유사 공통 보조 인덱스 수는 `4~7`개(`L2~L3`)로,
`S_ai` 기준 break-even(`18~19`)에 아직 미도달한다.

### 판정
- `S_ai`에서는 가설 3 지지(임계점 존재).
- 단, 현재 인덱스 수 구간에서는 역전 전.
- `S_rand`는 가설 3 불성립.

---

## 4-4. 가설 4 검증: "랜덤 I/O 제거가 아니라 위치 이동"
관측 지표: read/write/throughput 동시 관측

### 결과 예시
- `L2/S_ai`: read-per-insert 개선(`-12.06%`)인데도 `eps -12.80%`, `avg_latency +17.08%`
- `L1/S_ai`: read 개선인데 `data_writes_per_insert +64.71%`

### 판정
- 가설 4 지지.
- 단일 PK는 비용을 없애기보다 read/write/maintenance 경로로 재배치한다.
- 따라서 read 지표 단독 최적화는 최종 TPS/latency 개선을 보장하지 않는다.

---

## 5. 최종 판단 구조 (Issue #64 A/B/C)
Issue #64의 최종 판단 프레임으로 귀결:

- A. "조회 동등 + 랜덤 I/O 유의미 감소 + break-even 명확 -> 단일 PK 채택"
  - 현재 결과로는 기각.
  - 이유: `S_rand`는 일관 악화, `S_ai`도 레벨별 혼재.

- B. "차이 미미 -> 복합 PK 유지"
  - 운영 의사결정 관점에서 현재 채택.
  - 이유: 현재 인덱스 수(4~7)는 `S_ai` break-even(18~19) 미도달.

- C. "auto_increment에서만 유의미 -> monotonic clustering이 핵심"
  - 인과 해석 관점에서 채택.
  - 이유: `S_ai`와 `S_rand`의 방향성이 명확히 분리됨.

정리하면: **운영 선택은 B(현시점 복합 PK 유지), 구조적 인과는 C(monotonic 여부가 핵심)**.

---

## 6. 운영 권고
1. `S_rand`(non-monotonic 단일 PK)는 채택하지 않는다.
2. 단일 PK 전환 검토는 `S_ai` 계열(monotonic)로만 제한한다.
3. 단, 현재 인덱스 수 구간에서는 공간 역전 근거가 약하므로 즉시 전환하지 않는다.
4. 전환 검토 시 "read 절감"이 아니라 `per_insert` 정규화 + throughput/latency를 함께 기준으로 삼는다.

---

## 7. 신뢰도/한계
- `runs=5` 기준으로 일부 케이스 CV가 높다(예: `S_ai/L3 avg_ms_cv=24.641%`).
- sysbench percentile(`95th percentile`)이 `0.00`으로 출력되는 계측 한계가 있어, p95/p99는 본 결론 근거에서 제외했다.
- 따라서 본 결론은 mean/CV/CI95 + InnoDB counter 중심의 구조 판단 결과다.

---

## 8. 추가 검증 계획
1. percentile 계측 보강(sysbench p95 0.00 우회).
2. run 수 확대(10~15)로 신뢰구간 축소.
3. `L1/S_ai`의 `data_writes_per_insert` 급증 원인 분해(redo/flush/secondary maintenance).
