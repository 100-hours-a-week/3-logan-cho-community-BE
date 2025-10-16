package com.example.kaboocampostproject.domain.s3.dto.res;

import java.util.List;

public record PresignedUrlListResDTO(
        List<PresignedUrlResDTO> urls
) {}