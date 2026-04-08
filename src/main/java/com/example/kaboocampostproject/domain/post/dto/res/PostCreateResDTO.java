package com.example.kaboocampostproject.domain.post.dto.res;

import com.example.kaboocampostproject.domain.post.enums.PostImageStatus;
import lombok.Builder;

@Builder
public record PostCreateResDTO(
        String postId,
        String imageJobId,
        PostImageStatus imageStatus
) {
}
