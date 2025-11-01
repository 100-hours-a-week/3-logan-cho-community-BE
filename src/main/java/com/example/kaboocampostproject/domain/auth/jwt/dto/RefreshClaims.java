package com.example.kaboocampostproject.domain.auth.jwt.dto;

import com.example.kaboocampostproject.domain.member.entity.UserRole;

import java.time.Instant;

// Refresh 토큰에서 뽑은 클레임
public record RefreshClaims(
        Long    userId,
        UserRole  userRole,
        String  deviceId,
        String  refreshVersion,
        Instant expiresAt
) {}