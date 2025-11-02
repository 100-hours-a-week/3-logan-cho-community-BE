package com.example.kaboocampostproject.domain.auth.session.dto;

import com.example.kaboocampostproject.domain.member.entity.UserRole;
import lombok.Builder;

@Builder
public record UserAuthentication (
        String sessionId,
        Long memberId,
        UserRole role
) {
    public static UserAuthentication of (String sessionId, Long memberId, UserRole role) {
        return UserAuthentication.builder()
                .sessionId(sessionId)
                .memberId(memberId)
                .role(role)
                .build();
    }
}
