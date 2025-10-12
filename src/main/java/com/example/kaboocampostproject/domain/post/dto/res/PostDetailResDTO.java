package com.example.kaboocampostproject.domain.post.dto.res;

import lombok.Builder;

import java.time.Instant;
import java.util.List;

@Builder
public record PostDetailResDTO (
        String title,
        String content,
        List<String> imageUrls,
        long views,
        long likes,
        boolean amILiking,
        Instant createdAt,
        boolean isUpdated
) {
}
