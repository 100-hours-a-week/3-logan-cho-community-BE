package com.example.kaboocampostproject.domain.comment.dto;

import jakarta.annotation.Nullable;
import lombok.Builder;

import java.time.Instant;

@Builder
public record CommentSliceItem(
        String commentId,
        String content,
        Instant createdAt,
        boolean isUpdated,
        @Nullable AuthorProfile author,
        boolean isMine
) {
    // 작성자 프로필
    @Builder
    public record AuthorProfile(Long id, String name, String profileImageObjectKey) {}
}