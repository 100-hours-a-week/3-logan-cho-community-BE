package com.example.kaboocampostproject.domain.post.dto.res;

import com.example.kaboocampostproject.domain.post.enums.PostImageStatus;
import lombok.Builder;

import java.time.Instant;
import java.util.List;

@Builder
public record PostDetailResDTO (
        String cdnBaseUrl,
        String title,
        String content,
        List<String> imageObjectKeys,
        List<String> thumbnailKeys,
        PostImageStatus imageStatus,
        AuthorProfile authorProfile,
        long views,
        long likes,
        boolean amILiking,
        Instant createdAt,
        boolean isUpdated,
        boolean isMine
) {
    @Builder
    public record AuthorProfile(Long id, String name, String profileImageObjectKey) {}
}
