# post_likes PK 재검증 - 1단계 결과 (covering 선검증)

## 목적
- `src`에서 실제 사용하는 문제 쿼리가 스키마 전략별로 covering index로 동작하는지 선검증한다.
- 전략 비교 대상:
  - `C`: `PK(post_id, member_id)` (복합 PK)
  - `S_rand`: `PK(id BINARY(12) random)` (단일 PK, non-monotonic)
  - `S_ai`: `PK(id BIGINT AUTO_INCREMENT)` (단일 PK 대조군)

## 대상 쿼리 (`src` 기준)
- Feed 집계: `findPostLikeStats(...)`
- 좋아요 중복 체크: `existsByMemberIdAndPostId(...)`
- soft delete / bulk update 경로: `softDeleteAllByMemberId(...)`
- 쿼리 원문: `test/post-likes-benchmark/phase1-src-query-set.sql`

## 실행 조건
- 실행 스크립트: `test/post-likes-benchmark/run-phase1-covering-check.sh`
- 주요 파라미터:
  - `SCALE=medium`
  - `BUFFER_POOL_MB=48`
  - `MYSQL_MEMORY_LIMIT=768m` (384m에서는 OOM 발생)
- 결과 경로: `test/post-likes-benchmark/results/phase1_covering_medium/`

## 요약 결과
출처: `test/post-likes-benchmark/results/phase1_covering_medium/summary.tsv`

| case | query | key | using_index | extra |
|---|---|---|---|---|
| C | feed_aggregate | idx_feed_deleted_post_member | yes | Using where; Using index |
| S_rand | feed_aggregate | idx_feed_deleted_post_member | yes | Using where; Using index |
| S_ai | feed_aggregate | idx_feed_deleted_post_member | yes | Using where; Using index |
| C | exists_check | PRIMARY | no | (none) |
| S_rand | exists_check | uk_member_post_deleted | yes | Using where; Using index |
| S_ai | exists_check | uk_member_post_deleted | yes | Using where; Using index |
| C | bulk_update_path | uk_member_post_deleted | no | Using where; Using temporary |
| S_rand | bulk_update_path | uk_member_post_deleted | no | Using where; Using temporary |
| S_ai | bulk_update_path | uk_member_post_deleted | no | Using where; Using temporary |

## 해석
1. Feed 집계 쿼리
- 세 전략 모두 `idx_feed_deleted_post_member`로 covering range scan이 성립한다.
- 증거:
  - `test/post-likes-benchmark/results/phase1_covering_medium/C_analyze_feed.txt`
  - `test/post-likes-benchmark/results/phase1_covering_medium/S_rand_analyze_feed.txt`
  - `test/post-likes-benchmark/results/phase1_covering_medium/S_ai_analyze_feed.txt`

2. Exists(중복 체크) 쿼리
- `S_rand`, `S_ai`는 `uk_member_post_deleted`로 covering lookup이 성립한다.
- `C`는 `PRIMARY(post_id, member_id)` 접근 후 `deleted_at` 판별이 필요해 `Using index`가 나타나지 않는다.
- 증거:
  - `test/post-likes-benchmark/results/phase1_covering_medium/C_explain_exists.txt`
  - `test/post-likes-benchmark/results/phase1_covering_medium/S_rand_explain_exists.txt`
  - `test/post-likes-benchmark/results/phase1_covering_medium/S_ai_explain_exists.txt`

3. bulk update 경로
- 세 전략 모두 `uk_member_post_deleted` range 접근으로 시작하지만, `UPDATE` 특성상 covering 판정 대상이 아니다.
- `Using temporary`가 공통으로 나타나며, 이는 이후 2/3단계에서 실제 I/O/쓰기 비용으로 계량해야 한다.
- 증거:
  - `test/post-likes-benchmark/results/phase1_covering_medium/C_explain_bulk_update.txt`
  - `test/post-likes-benchmark/results/phase1_covering_medium/S_rand_explain_bulk_update.txt`
  - `test/post-likes-benchmark/results/phase1_covering_medium/S_ai_explain_bulk_update.txt`

## 결론 (1단계)
- Feed 집계 경로는 전략 간 covering 성립 여부의 차이가 없다.
- Exists 경로는 단일 PK 전략(`S_rand`, `S_ai`)이 covering 관점에서 더 직접적이다.
- 따라서 2단계부터는 “조회 가능성”보다 “인덱스 크기와 랜덤 I/O 누적 비용”을 중심으로 비교하는 것이 타당하다.
