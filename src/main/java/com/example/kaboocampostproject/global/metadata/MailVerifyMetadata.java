package com.example.kaboocampostproject.global.metadata;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

@Getter
@RequiredArgsConstructor
public enum MailVerifyMetadata {
    EMAIL_VERIFICATION(
            "/api/auth/verify-email",
            "[Millions] 이메일 인증을 완료해주세요",
            10  // TTL (분)
    ),
    PASSWORD_RESET(
            "/api/auth/reset-password",
            "[Millions] 비밀번호 재설정 링크입니다",
            15
    );

    private final String endpoint;
    private final String subject;
    private final int ttlMinutes;
}