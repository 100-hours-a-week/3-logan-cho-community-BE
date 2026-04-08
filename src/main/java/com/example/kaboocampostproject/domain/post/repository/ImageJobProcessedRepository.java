package com.example.kaboocampostproject.domain.post.repository;

import com.example.kaboocampostproject.domain.post.document.ImageJobProcessedDocument;
import org.springframework.data.mongodb.repository.MongoRepository;

import java.util.Optional;

public interface ImageJobProcessedRepository extends MongoRepository<ImageJobProcessedDocument, String> {

    Optional<ImageJobProcessedDocument> findByImageJobId(String imageJobId);
}
