package com.example.kaboocampostproject.domain.post.dto.res;

import lombok.Builder;

import java.time.Instant;

@Builder
public record PostSliceItem(
        String postId,
        String title,
        long views,
        Instant createdAt,
        AuthorProfile author,
        long commentCount,
        boolean amILike
) {
    // 작성자 프로필
    @Builder
    public record AuthorProfile(Long id, String name, String profileImageObjectKey) {}
}