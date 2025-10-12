package com.example.kaboocampostproject.domain.comment.repository.impl;

import com.example.kaboocampostproject.domain.comment.document.CommentDocument;
import com.example.kaboocampostproject.domain.comment.repository.CommentCustomRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.util.List;

@Repository
@RequiredArgsConstructor
public class CommentCustomRepositoryImpl implements CommentCustomRepository {

    private final MongoTemplate mongo;

    private static final String COLLECTION = "comments";

    private void includeCommentSimpleFields(Query query) {
        query.fields()
                .include(CommentDocument.CommentFields.id)
                .include(CommentDocument.CommentFields.content)
                .include(CommentDocument.CommentFields.authorId)
                .include(CommentDocument.CommentFields.createdAt);
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
}
