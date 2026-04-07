package com.example.kaboocampostproject.domain.post.repository.impl;

import com.example.kaboocampostproject.domain.post.document.ImageJobOutboxDocument;
import com.example.kaboocampostproject.domain.post.enums.ImageJobOutboxStatus;
import com.example.kaboocampostproject.domain.post.repository.ImageJobOutboxClaimRepository;
import com.mongodb.client.result.UpdateResult;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.FindAndModifyOptions;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.data.mongodb.core.query.Update;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.util.Optional;

@Repository
@RequiredArgsConstructor
public class ImageJobOutboxClaimRepositoryImpl implements ImageJobOutboxClaimRepository {

    private final MongoTemplate mongoTemplate;

    @Override
    public Optional<ImageJobOutboxDocument> claimNextRelayCandidate(Instant now, Instant leaseUntil, String processingOwner) {
        Query query = new Query(new Criteria().orOperator(
                new Criteria().andOperator(
                        Criteria.where("status").is(ImageJobOutboxStatus.PENDING),
                        Criteria.where("nextAttemptAt").lte(now)
                ),
                new Criteria().andOperator(
                        Criteria.where("status").is(ImageJobOutboxStatus.PROCESSING),
                        Criteria.where("nextAttemptAt").lte(now)
                )
        ));
        query.with(Sort.by(Sort.Direction.ASC, "createdAt"));

        Update update = new Update()
                .set("status", ImageJobOutboxStatus.PROCESSING)
                .set("processingOwner", processingOwner)
                .set("nextAttemptAt", leaseUntil);

        ImageJobOutboxDocument claimed = mongoTemplate.findAndModify(
                query,
                update,
                FindAndModifyOptions.options().returnNew(true),
                ImageJobOutboxDocument.class
        );
        return Optional.ofNullable(claimed);
    }

    @Override
    public boolean completeRelayAttempt(String outboxId, String processingOwner, boolean published, Instant nextAttemptAt, String lastError) {
        Query query = new Query(new Criteria().andOperator(
                Criteria.where("_id").is(outboxId),
                Criteria.where("status").is(ImageJobOutboxStatus.PROCESSING),
                Criteria.where("processingOwner").is(processingOwner)
        ));

        Update update = new Update()
                .set("processingOwner", null);

        if (published) {
            update.set("status", ImageJobOutboxStatus.PUBLISHED)
                    .set("publishedAt", Instant.now())
                    .set("lastError", null);
        } else {
            update.set("status", ImageJobOutboxStatus.PENDING)
                    .set("nextAttemptAt", nextAttemptAt)
                    .set("lastError", lastError)
                    .inc("publishAttempts", 1);
        }

        UpdateResult result = mongoTemplate.updateFirst(query, update, ImageJobOutboxDocument.class);
        return result.getModifiedCount() == 1;
    }
}
