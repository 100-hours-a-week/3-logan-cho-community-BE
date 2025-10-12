package com.example.kaboocampostproject.domain.post.dto.req;

import java.util.List;

public record PostUpdateReqDTO(
        String postId,
        String title,
        String contents,
        List<String> imageUrls
) {
}
