package com.example.kaboocampostproject.domain.auth.dto.req;

public record VerifyEmailReqDTO(
        String email,
        String code
) {}