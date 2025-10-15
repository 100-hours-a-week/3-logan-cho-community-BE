package com.example.kaboocampostproject.domain.s3.dto.res;

public record PresignedUrlResDTO(
        String presignedUrl,
        String objectKey
) {}