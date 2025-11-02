package com.example.kaboocampostproject.domain.member.entity;

public enum UserRole {
    ROLE_USER,
    ROLE_ADMIN;

    public static UserRole of(String role) {
        return UserRole.valueOf(role);
    }
}
