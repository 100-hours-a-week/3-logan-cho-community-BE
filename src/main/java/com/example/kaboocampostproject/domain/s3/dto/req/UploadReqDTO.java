package com.example.kaboocampostproject.domain.s3.dto.req;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public record UploadReqDTO(
        @NotBlank String fileName,
        @NotNull String mimeType
) {}