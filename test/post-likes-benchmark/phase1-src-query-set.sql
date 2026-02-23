-- Phase 1: src 기반 커버링 검증 대상 쿼리 세트
-- Source:
-- - PostLikeRepository.findPostLikeStats(...)
-- - PostLikeRepository.existsByMemberIdAndPostId(...)
-- - PostLikeRepository.softDeleteAllByMemberId(...)

-- Q1) Feed 집계 (IN 리스트 집계 + amILiking)
SELECT pl.post_id,
       COUNT(*) AS like_count,
       MAX(CASE WHEN pl.member_id = ? THEN TRUE ELSE FALSE END) AS amILiking
FROM post_likes_case pl
WHERE pl.post_id IN (?, ?, ?, ...)
  AND pl.deleted_at IS NULL
GROUP BY pl.post_id;

-- Q2) 좋아요 중복 체크 (exists 경로)
SELECT 1
FROM post_likes_case
WHERE post_id = ?
  AND member_id = ?
  AND deleted_at IS NULL
LIMIT 1;

-- Q3) soft delete / bulk update 경로
UPDATE post_likes_case
SET deleted_at = CURRENT_TIMESTAMP(6)
WHERE member_id = ?
  AND deleted_at IS NULL;
