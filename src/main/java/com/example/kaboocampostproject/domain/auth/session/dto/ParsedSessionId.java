package com.example.kaboocampostproject.domain.auth.session.dto;

public record ParsedSessionId (
        String sessionKey,
        String tag
) {
}
