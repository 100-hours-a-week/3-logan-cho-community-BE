package com.example.kaboocampostproject.domain.post.repository;

import com.example.kaboocampostproject.domain.comment.document.CommentDocument;
import com.example.kaboocampostproject.domain.post.document.PostDocument;
import org.springdoc.core.converters.models.Pageable;
import org.springframework.data.domain.Page;
import org.springframework.data.mongodb.repository.MongoRepository;

import java.util.Optional;

public interface PostMongoRepository extends MongoRepository<PostDocument, String> , PostCustomRepository {
    Optional<PostDocument> findByIdAndDeletedAtIsNull(String id);
}
