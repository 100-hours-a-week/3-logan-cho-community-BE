package com.example.kaboocampostproject.domain.s3.dto.req;

import jakarta.validation.constraints.NotEmpty;

import java.util.List;

public record UploadListReqDTO(
        @NotEmpty
        List<UploadReqDTO> files
) {}