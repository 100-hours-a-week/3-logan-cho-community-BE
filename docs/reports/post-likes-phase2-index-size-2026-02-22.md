# post_likes PK 재검증 - 2단계 결과 (인덱스 구조/공간/임계점)

## 목적
- 복합 PK(`C`)와 단일 PK(`S_rand`, `S_ai`)에서 인덱스 공간 차이를 정량화한다.
- 단일 PK의 추가 비용(`idx_feed_deleted_post_member`)을 공통 보조인덱스 절감으로 상쇄할 수 있는지 break-even을 계산한다.

## 실험 구성
- 실행 스크립트: `test/post-likes-benchmark/run-phase2-index-size.sh`
- 고정 조건:
  - `SCALE=medium`
  - `BUFFER_POOL_MB=48`
  - `MYSQL_MEMORY_LIMIT=768m`
  - `post_id BINARY(12)` 고정
- 케이스:
  - `C`: `PK(post_id, member_id)`
  - `S_rand`: `PK(id BINARY(12) random)` + `idx_feed_deleted_post_member`
  - `S_ai`: `PK(id AUTO_INCREMENT)` + `idx_feed_deleted_post_member`
- 레벨:
  - `L1`: 공통 인덱스 2개(`uk_member_post_deleted`, `idx_member`)
  - `L2`: 공통 인덱스 4개
  - `L3`: 공통 인덱스 7개
- 공정성 보정:
  - 모든 케이스의 INSERT 입력 순서를 `source_id` 순으로 동일화하여 적재 순서 편향을 제거함.

## 원본 결과
출처: `test/post-likes-benchmark/results/phase2_index_size_medium/summary.tsv`

| level | case | primary_mb | common_secondary_mb | extra_single_mb |
|---|---|---:|---:|---:|
| L1 | C | 71.656 | 76.218 | 0.000 |
| L1 | S_rand | 88.641 | 98.360 | 58.750 |
| L1 | S_ai | 51.594 | 85.219 | 51.641 |
| L2 | C | 71.656 | 136.421 | 0.000 |
| L2 | S_rand | 88.641 | 144.516 | 58.750 |
| L2 | S_ai | 51.594 | 124.343 | 51.641 |
| L3 | C | 71.656 | 271.312 | 0.000 |
| L3 | S_rand | 88.641 | 285.438 | 58.750 |
| L3 | S_ai | 51.594 | 252.203 | 51.641 |

## break-even 계산 결과
출처: `test/post-likes-benchmark/results/phase2_index_size_medium/break_even.tsv`

| level | variant | extra_single_cost_mb | common_secondary_saving_total_mb | saving_per_secondary_mb | break_even_k |
|---|---|---:|---:|---:|---:|
| L1 | S_rand | 58.750 | -22.142 | -11.071 | inf |
| L2 | S_rand | 58.750 | -8.095 | -2.024 | inf |
| L3 | S_rand | 58.750 | -14.126 | -2.018 | inf |
| L1 | S_ai | 51.641 | -9.001 | -4.500 | inf |
| L2 | S_ai | 51.641 | 12.078 | 3.019 | 18 |
| L3 | S_ai | 51.641 | 19.109 | 2.730 | 19 |

## 해석
1. Primary(클러스터드) 크기
- `S_ai`는 `C` 대비 primary가 작다 (`51.594MB` vs `71.656MB`).
- `S_rand`는 오히려 primary가 더 크다 (`88.641MB`).
- 랜덤 PK(`S_rand`)는 페이지 분할/공간 비효율로 클러스터드 인덱스가 커질 수 있음을 보여준다.

2. 공통 보조인덱스 누적 효과
- `S_ai`는 공통 보조인덱스 개수가 늘수록(`L2`, `L3`) `C` 대비 절감이 발생한다.
- `S_rand`는 공통 보조인덱스에서도 절감이 아니라 증가가 나타난다.
- 즉 “단일 PK”라고 해서 항상 보조인덱스가 작아지는 것이 아니라, PK 특성(특히 monotonic 여부)이 크게 작용한다.

3. 단일 PK 추가 비용 상쇄 가능성
- `S_ai` 기준으로 `idx_feed_deleted_post_member` 추가 비용(`~51.6MB`)을 상쇄하려면
  공통 보조인덱스가 대략 `18~19개` 수준은 필요하다는 계산이 나온다.
- 현재 `src` 유사 수준(`L2~L3`, 공통 4~7개)에서는 상쇄에 도달하지 못한다.
- `S_rand`는 본 실험 조건에서 break-even이 성립하지 않는다(`inf`).

## 결론 (2단계)
- “보조인덱스가 많아질수록 단일 PK가 유리해진다”는 명제는 `S_ai`(monotonic PK)에서만 부분적으로 성립한다.
- `S_rand`(non-monotonic PK)는 공간 측면에서 역효과가 발생해, 단일 PK 채택 근거가 약하다.
- 따라서 3단계 랜덤 I/O/성능 실측은 `C vs S_rand vs S_ai`를 유지하되,
  최종 해석은 “단일 PK 일반론”이 아니라 “PK 생성 패턴(단조/비단조) 분리”로 가져가는 것이 타당하다.
