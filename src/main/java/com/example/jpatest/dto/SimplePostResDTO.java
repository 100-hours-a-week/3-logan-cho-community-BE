package com.example.jpatest.dto;

import java.time.LocalDateTime;

public record SimplePostResDTO(
        Long postId,
        String title,
        Long creatorId,
        String creatorName,
        LocalDateTime createdAt

) {
}
