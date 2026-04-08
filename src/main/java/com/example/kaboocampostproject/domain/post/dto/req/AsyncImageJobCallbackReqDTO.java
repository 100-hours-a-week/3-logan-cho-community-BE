package com.example.kaboocampostproject.domain.post.dto.req;

import com.example.kaboocampostproject.domain.post.enums.PostImageStatus;

import java.util.List;

public record AsyncImageJobCallbackReqDTO(
        String imageJobId,
        PostImageStatus imageStatus,
        List<String> finalImageKeys,
        List<String> thumbnailKeys,
        String failureReason
) {
}
