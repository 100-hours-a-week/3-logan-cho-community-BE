package com.example.kaboocampostproject.domain.member.dto.request;

public record RecoverMemberReqDTO(
        String email,
        String newPassword,
        String verificationCode
) {}