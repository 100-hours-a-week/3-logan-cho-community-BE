package com.example.kaboocampostproject.domain.post.batch;

import com.example.kaboocampostproject.domain.comment.repository.CommentMongoRepository;
import com.example.kaboocampostproject.domain.like.repository.PostLikeRepository;
import com.example.kaboocampostproject.domain.post.repository.PostMongoRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
public class PostCountSyncBatchService {

    private final PostMongoRepository postRepository;
    private final PostLikeRepository postLikeRepository;
    private final CommentMongoRepository commentRepository;

    /**
     * 매일 새벽 3시에 실행되는 배치 작업
     * updatedAt이 오늘인 게시물들의 좋아요/댓글 개수를 실제 값과 동기화
     */
    @Scheduled(cron = "0 0 3 * * *")
    public void syncPostCounts() {
        log.info("[PostCountSync] 배치 작업 시작");

        try {
            // 오늘 업데이트된 게시물 ID 목록 조회
            List<String> postIds = postRepository.findPostIdsUpdatedToday();
            log.info("[PostCountSync] 동기화 대상 게시물 개수: {}", postIds.size());

            int syncedCount = 0;
            int errorCount = 0;

            for (String postId : postIds) {
                try {
                    syncPostCount(postId);
                    syncedCount++;
                } catch (Exception e) {
                    errorCount++;
                    log.error("[PostCountSync] 게시물 동기화 실패 - postId: {}, error: {}", postId, e.getMessage());
                }
            }

            log.info("[PostCountSync] 배치 작업 완료 - 성공: {}, 실패: {}", syncedCount, errorCount);
        } catch (Exception e) {
            log.error("[PostCountSync] 배치 작업 실패", e);
        }
    }

    /**
     * 개별 게시물의 카운트 동기화
     */
    private void syncPostCount(String postId) {
        // 실제 좋아요 개수 조회 (MySQL)
        long actualLikeCount = postLikeRepository.countByPostId(postId);

        // 실제 댓글 개수 조회 (MongoDB)
        long actualCommentCount = commentRepository.countByPostIdAndDeletedAtIsNull(postId);

        // MongoDB의 게시물 카운트 값 업데이트
        postRepository.syncCounts(postId, actualLikeCount, actualCommentCount);

        log.debug("[PostCountSync] 게시물 동기화 완료 - postId: {}, likeCount: {}, commentCount: {}",
                postId, actualLikeCount, actualCommentCount);
    }
}