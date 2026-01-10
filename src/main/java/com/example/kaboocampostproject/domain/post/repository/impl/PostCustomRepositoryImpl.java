package com.example.kaboocampostproject.domain.post.repository.impl;

import com.example.kaboocampostproject.domain.post.document.PostDocument;
import com.example.kaboocampostproject.domain.post.dto.req.PostUpdateReqDTO;
import com.example.kaboocampostproject.domain.post.dto.res.PostSimple;
import com.example.kaboocampostproject.domain.post.repository.PostCustomRepository;
import com.mongodb.client.result.UpdateResult;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.data.mongodb.core.query.Update;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

@Repository
@RequiredArgsConstructor
public class PostCustomRepositoryImpl implements PostCustomRepository {

    private final MongoTemplate mongo;

    private static final String COLLECTION = "posts";




    @Override
    public List<String> findImageObjectKeys(String postId, Long memberId) {
        Query query = new Query(
                Criteria.where("_id").is(postId)
                        .and("authorId").is(memberId)
                        .and("deletedAt").is(null)
        );
        query.fields().include("imageObjectKeys"); // 이미지만 가져오기
        PostDocument post = mongo.findOne(query, PostDocument.class);
        return post != null ? post.getImageObjectKeys() : new ArrayList<>();
    }

    @Override
    public boolean updatePostFields(Long memberId, String postId, PostUpdateReqDTO req, List<String> remainingImages) {
        // 작성자 아이디, 기 삭제여부 검증
        Query query = new Query(
                Criteria.where("_id").is(postId)
                        .and("authorId").is(memberId)
                        .and("deletedAt").is(null)
        );

        Update update = new Update();
        if (req.title() != null) update.set("title", req.title());
        if (req.content() != null) update.set("content", req.content());
        if (remainingImages != null) update.set("imageObjectKeys", remainingImages);

        UpdateResult result = mongo.updateFirst(query, update, PostDocument.class);
        return result.getModifiedCount() > 0;
    }


    // 조회수 원자적 증가
    @Override
    public void incrementViews(String postId, long count) {
        Query query = new Query(Criteria.where(PostDocument.PostFields.id).is(postId)
                .and(PostDocument.PostFields.deletedAt).is(null));
        Update update = new Update().inc(PostDocument.PostFields.views, count);
        mongo.updateFirst(query, update, PostDocument.class);

    }

    // 좋아요 개수 원자적 증가
    @Override
    public void incrementLikeCount(String postId) {
        Query query = new Query(Criteria.where(PostDocument.PostFields.id).is(postId)
                .and(PostDocument.PostFields.deletedAt).is(null));
        Update update = new Update().inc(PostDocument.PostFields.likeCount, 1);
        mongo.updateFirst(query, update, PostDocument.class);
    }

    // 좋아요 개수 원자적 감소
    @Override
    public void decrementLikeCount(String postId) {
        Query query = new Query(Criteria.where(PostDocument.PostFields.id).is(postId)
                .and(PostDocument.PostFields.deletedAt).is(null));
        Update update = new Update().inc(PostDocument.PostFields.likeCount, -1);
        mongo.updateFirst(query, update, PostDocument.class);
    }

    // 댓글 개수 원자적 증가
    @Override
    public void incrementCommentCount(String postId) {
        Query query = new Query(Criteria.where(PostDocument.PostFields.id).is(postId)
                .and(PostDocument.PostFields.deletedAt).is(null));
        Update update = new Update().inc(PostDocument.PostFields.commentCount, 1);
        mongo.updateFirst(query, update, PostDocument.class);
    }

    // 댓글 개수 원자적 감소
    @Override
    public void decrementCommentCount(String postId) {
        Query query = new Query(Criteria.where(PostDocument.PostFields.id).is(postId)
                .and(PostDocument.PostFields.deletedAt).is(null));
        Update update = new Update().inc(PostDocument.PostFields.commentCount, -1);
        mongo.updateFirst(query, update, PostDocument.class);
    }

    //================== 배치 동기화 ====================

    // 오늘 업데이트된 게시물 ID 목록 조회
    @Override
    public List<String> findPostIdsUpdatedToday() {
        Instant startOfToday = Instant.now().atZone(java.time.ZoneId.systemDefault())
                .toLocalDate()
                .atStartOfDay(java.time.ZoneId.systemDefault())
                .toInstant();

        Query query = new Query(
                Criteria.where(PostDocument.PostFields.updatedAt).gte(startOfToday)
                        .and(PostDocument.PostFields.deletedAt).is(null)
        );
        query.fields().include(PostDocument.PostFields.id);

        return mongo.find(query, PostDocument.class, COLLECTION)
                .stream()
                .map(PostDocument::getId)
                .toList();
    }

    // 게시물의 카운트 값 동기화
    @Override
    public void syncCounts(String postId, long likeCount, long commentCount) {
        Query query = new Query(
                Criteria.where(PostDocument.PostFields.id).is(postId)
                        .and(PostDocument.PostFields.deletedAt).is(null)
        );
        Update update = new Update()
                .set(PostDocument.PostFields.likeCount, likeCount)
                .set(PostDocument.PostFields.commentCount, commentCount);

        mongo.updateFirst(query, update, PostDocument.class);
    }

    //================== 커서키반 페이징 ====================

    private void includePostSimpleFields(Query query) {
        query.fields()
            .include(PostDocument.PostFields.id)
            .include(PostDocument.PostFields.title)
            .include(PostDocument.PostFields.views)
            .include(PostDocument.PostFields.authorId)
            .include(PostDocument.PostFields.createdAt)
            .include(PostDocument.PostFields.likeCount)
            .include(PostDocument.PostFields.commentCount);
    }


    @Override
    public List<PostSimple> findFirstByCreatedAt(int sizePlusOne) {
        Query q = new Query()
                .addCriteria(Criteria.where(PostDocument.PostFields.deletedAt).is(null))
                .with(Sort.by(
                        Sort.Order.desc(PostDocument.PostFields.createdAt),
                        Sort.Order.desc(PostDocument.PostFields.id)
                ))
                .limit(sizePlusOne);

        includePostSimpleFields(q);

        return mongo.find(q, PostSimple.class, COLLECTION);
    }

    @Override
    public List<PostSimple> findNextByCreatedAt(Instant createdAt, String id, int sizePlusOne) {
        Criteria cursorCut = new Criteria().orOperator(
                Criteria.where(PostDocument.PostFields.createdAt).lt(createdAt),
                new Criteria().andOperator(
                        Criteria.where(PostDocument.PostFields.createdAt).is(createdAt),
                        Criteria.where(PostDocument.PostFields.id).lt(id)
                )
        );

        Query q = new Query()
                .addCriteria(new Criteria().andOperator(
                        Criteria.where(PostDocument.PostFields.deletedAt).is(null),
                        cursorCut
                ))
                .with(Sort.by(
                        Sort.Order.desc(PostDocument.PostFields.createdAt),
                        Sort.Order.desc(PostDocument.PostFields.id)
                ))
                .limit(sizePlusOne);

        includePostSimpleFields(q);

        return mongo.find(q, PostSimple.class, COLLECTION);
    }

    @Override
    public List<PostSimple> findFirstByView(int sizePlusOne) {
        Query q = new Query()
                .addCriteria(Criteria.where(PostDocument.PostFields.deletedAt).is(null))
                .with(Sort.by(
                        Sort.Order.desc(PostDocument.PostFields.views),
                        Sort.Order.desc(PostDocument.PostFields.createdAt),
                        Sort.Order.desc(PostDocument.PostFields.id)
                ))
                .limit(sizePlusOne);

        includePostSimpleFields(q);

        return mongo.find(q, PostSimple.class, COLLECTION);
    }

    @Override
    public List<PostSimple> findNextByView(long view, Instant createdAt, String id, int sizePlusOne) {
        Criteria cursorCut = new Criteria().orOperator(
                Criteria.where(PostDocument.PostFields.views).lt(view),
                new Criteria().andOperator(
                        Criteria.where(PostDocument.PostFields.views).is(view),
                        Criteria.where(PostDocument.PostFields.createdAt).lt(createdAt)
                ),
                new Criteria().andOperator(
                        Criteria.where(PostDocument.PostFields.views).is(view),
                        Criteria.where(PostDocument.PostFields.createdAt).is(createdAt),
                        Criteria.where(PostDocument.PostFields.id).lt(id)
                )
        );

        Query q = new Query()
                .addCriteria(new Criteria().andOperator(
                        Criteria.where(PostDocument.PostFields.deletedAt).is(null),
                        cursorCut
                ))
                .with(Sort.by(
                        Sort.Order.desc(PostDocument.PostFields.views),
                        Sort.Order.desc(PostDocument.PostFields.createdAt),
                        Sort.Order.desc(PostDocument.PostFields.id)
                ))
                .limit(sizePlusOne);

        includePostSimpleFields(q);

        return mongo.find(q, PostSimple.class, COLLECTION);
    }

    //================== 소프트 딜리트 ====================

    @Override
    public boolean softDelete(String postId, Long memberId) {

        // 작성자 아이디, 기 삭제여부 검증
        Query query = new Query(
                Criteria.where("_id").is(postId)
                        .and("authorId").is(memberId)
                        .and("deletedAt").is(null)
        );
        Update update = new Update().set("deletedAt", Instant.now());
        UpdateResult result = mongo.updateFirst(query, update, PostDocument.class);

        return result.getModifiedCount() > 0;
    }

}
