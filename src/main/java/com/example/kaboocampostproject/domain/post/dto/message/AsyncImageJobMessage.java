package com.example.kaboocampostproject.domain.post.dto.message;

import java.time.Instant;
import java.util.List;

public record AsyncImageJobMessage(
        String imageJobId,
        String postId,
        String bucket,
        List<String> tempImageKeys,
        String callbackUrl,
        Instant requestedAt
) {
}
