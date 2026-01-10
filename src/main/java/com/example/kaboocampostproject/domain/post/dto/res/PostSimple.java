package com.example.kaboocampostproject.domain.post.dto.res;

import org.springframework.data.mongodb.core.mapping.Field;

import java.time.Instant;

public record PostSimple(
            @Field("_id") String postId,
            String title,
            long views,
            Long authorId,
            Instant createdAt,
            long likeCount,
            long commentCount
){}