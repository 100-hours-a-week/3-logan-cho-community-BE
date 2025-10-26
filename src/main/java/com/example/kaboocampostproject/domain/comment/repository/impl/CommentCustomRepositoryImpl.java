package com.example.kaboocampostproject.domain.comment.repository.impl;

import com.example.kaboocampostproject.domain.comment.document.CommentDocument;
import com.example.kaboocampostproject.domain.comment.repository.CommentCustomRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.data.mongodb.core.query.Update;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.util.List;

@Repository
@RequiredArgsConstructor
public class CommentCustomRepositoryImpl implements CommentCustomRepository {

    private final MongoTemplate mongo;

    private static final String COLLECTION = "comments";

    @Override
    public boolean updateCommentContent(String commentId, Long authorId, String newContent) {
        Query query = new Query(
                Criteria.where("_id").is(commentId)
                        .and("authorId").is(authorId)
                        .and("deletedAt").is(null)
        );

        Update update = new Update()
                .set("content", newContent)
                .set("updatedAt", Instant.now());

        var result = mongo.updateFirst(query, update, CommentDocument.class);
        return result.getModifiedCount() > 0;
    }


    //================== 커서 키반 페이징 ====================

    private void includeCommentSimpleFields(Query query) {
        query.fields()
                .include(CommentDocument.CommentFields.id)
                .include(CommentDocument.CommentFields.content)
                .include(CommentDocument.CommentFields.authorId)
                .include(CommentDocument.CommentFields.createdAt)
                .include(CommentDocument.CommentFields.updatedAt)
                .include(CommentDocument.CommentFields.postId);
    }

    // 최신 순 첫 페이지
    @Override
    public List<CommentDocument> findFirstByPostIdOrderByCreatedAtDesc(String postId, int sizePlusOne) {
        Query q = new Query()
                .addCriteria(new Criteria().andOperator(
                        Criteria.where(CommentDocument.CommentFields.postId).is(postId),
                        Criteria.where(CommentDocument.CommentFields.deletedAt).is(null)
                ))
                .with(Sort.by(
                        Sort.Order.desc(CommentDocument.CommentFields.createdAt),
                        Sort.Order.desc(CommentDocument.CommentFields.id)
                ))
                .limit(sizePlusOne);

        includeCommentSimpleFields(q);
        return mongo.find(q, CommentDocument.class, COLLECTION);
    }

    // 최신 순 다음 페이지
    @Override
    public List<CommentDocument> findNextByPostIdOrderByCreatedAtDesc(String postId, Instant createdAt, String id, int sizePlusOne) {
        Criteria cursorCut = new Criteria().orOperator(
                Criteria.where(CommentDocument.CommentFields.createdAt).lt(createdAt),
                new Criteria().andOperator(
                        Criteria.where(CommentDocument.CommentFields.createdAt).is(createdAt),
                        Criteria.where(CommentDocument.CommentFields.id).lt(id)
                )
        );

        Query q = new Query()
                .addCriteria(new Criteria().andOperator(
                        Criteria.where(CommentDocument.CommentFields.postId).is(postId),
                        Criteria.where(CommentDocument.CommentFields.deletedAt).is(null),
                        cursorCut
                ))
                .with(Sort.by(
                        Sort.Order.desc(CommentDocument.CommentFields.createdAt),
                        Sort.Order.desc(CommentDocument.CommentFields.id)
                ))
                .limit(sizePlusOne);

        includeCommentSimpleFields(q);
        return mongo.find(q, CommentDocument.class, COLLECTION);
    }



    //================== 소프트 딜리트 ====================

    // 댓글 id 기준
    @Override
    public boolean softDeleteByCommentId(String commentId, Long authorId) {
        Query query = new Query(
                Criteria.where("_id").is(commentId)
                        .and("authorId").is(authorId)
                        .and("deletedAt").is(null)
        );
        Update update = new Update().set("deletedAt", Instant.now());
        var result = mongo.updateFirst(query, update, CommentDocument.class);
        return result.getModifiedCount() > 0;
    }

    // 게시물 작성자 기준
    @Override
    public void softDeleteByAuthorId(Long authorId) {
        Query query = Query.query(Criteria.where("authorId").is(authorId));
        Update update = new Update().set("deletedAt", Instant.now());
        mongo.updateMulti(query, update, CommentDocument.class);
    }

    // 게시물 아이디 기준
    @Override
    public void softDeleteByPostId(String postId) {
        Query query = Query.query(Criteria.where("postId").is(postId));
        Update update = new Update().set("deletedAt", Instant.now());
        mongo.updateMulti(query, update, CommentDocument.class);
    }


}
