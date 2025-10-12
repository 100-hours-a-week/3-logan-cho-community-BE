package com.example.kaboocampostproject.domain.comment.repository;

import com.example.kaboocampostproject.domain.comment.document.CommentDocument;
import org.springframework.data.mongodb.repository.MongoRepository;

import java.util.Optional;

public interface CommentMongoRepository  extends MongoRepository<CommentDocument, String>, CommentCustomRepository {
    Optional<CommentDocument> findByIdAndDeletedAtIsNull(String id);
}
