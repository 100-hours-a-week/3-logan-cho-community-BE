package com.example.kaboocampostproject.domain.comment.repository;

import com.example.kaboocampostproject.domain.comment.document.CommentDocument;

import java.time.Instant;
import java.util.List;

public interface CommentCustomRepository {
    List<CommentDocument> findFirstByPostIdOrderByCreatedAtDesc(String postId, int sizePlusOne);
    List<CommentDocument> findNextByPostIdOrderByCreatedAtDesc(String postId, Instant createdAt, String id, int sizePlusOne);
}