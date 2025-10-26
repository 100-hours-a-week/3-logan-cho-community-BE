package com.example.kaboocampostproject.domain.post.dto.req;

import com.mongodb.lang.Nullable;

import java.util.List;

public record PostUpdateReqDTO(
        String postId,
        @Nullable String title,
        @Nullable String content,
        @Nullable List<String> addedImageObjectKeys,
        @Nullable List<String> removedImageObjectKeys
) {
}
