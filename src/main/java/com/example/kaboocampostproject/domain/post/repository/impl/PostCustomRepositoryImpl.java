package com.example.kaboocampostproject.domain.post.repository.impl;

import com.example.kaboocampostproject.domain.post.document.PostDocument;
import com.example.kaboocampostproject.domain.post.dto.res.PostSimple;
import com.example.kaboocampostproject.domain.post.repository.PostCustomRepository;
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
public class PostCustomRepositoryImpl implements PostCustomRepository {

    private final MongoTemplate mongo;

    private static final String COLLECTION = "posts";

    // 조회수 원자적 증가
    @Override
    public void incrementViews(String postId, long count) {
        Query query = new Query(Criteria.where(PostDocument.PostFields.id).is(postId));
        Update update = new Update().inc(PostDocument.PostFields.views, count);
        mongo.updateFirst(query, update, PostDocument.class);

    }

    private void includePostSimpleFields(Query query) {
        query.fields()
            .include(PostDocument.PostFields.id)
            .include(PostDocument.PostFields.title)
            .include(PostDocument.PostFields.views)
            .include(PostDocument.PostFields.authorId)
            .include(PostDocument.PostFields.createdAt);
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
}
