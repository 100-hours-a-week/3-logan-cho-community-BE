package com.example.kaboocampostproject.domain.auth.jwt.dto;

import com.example.kaboocampostproject.domain.member.entity.UserRole;

public record AccessClaims(
        long userId,
        UserRole userRole
) {
}
