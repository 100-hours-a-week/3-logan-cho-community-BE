package com.example.kaboocampostproject.domain.post.repository;

import com.example.kaboocampostproject.domain.post.document.ImageJobOutboxDocument;
import com.example.kaboocampostproject.domain.post.enums.ImageJobOutboxStatus;
import org.springframework.data.mongodb.repository.MongoRepository;

import java.time.Instant;
import java.util.List;

public interface ImageJobOutboxRepository extends MongoRepository<ImageJobOutboxDocument, String> {

    List<ImageJobOutboxDocument> findTop100ByStatusAndNextAttemptAtLessThanEqualOrderByCreatedAtAsc(
            ImageJobOutboxStatus status,
            Instant nextAttemptAt
    );
}
