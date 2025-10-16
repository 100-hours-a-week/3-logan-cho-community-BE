package com.example.kaboocampostproject.domain.auth.dto;

public record LoginReqDTO (
        String email,
        String password,
        String deviceId
){
}
