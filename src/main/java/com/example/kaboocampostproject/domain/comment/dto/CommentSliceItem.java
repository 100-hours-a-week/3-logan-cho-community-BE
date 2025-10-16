package com.example.kaboocampostproject.domain.comment.dto;

import lombok.Builder;

import java.time.Instant;

@Builder
public record CommentSliceItem(
        String commentId,
        String content,
        Instant createdAt,
        boolean isUpdated,
        AuthorProfile author
) {
    // 작성자 프로필
    @Builder
    public record AuthorProfile(Long id, String name, String profileImageUrl) {}
}