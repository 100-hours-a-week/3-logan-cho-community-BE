package com.example.kaboocampostproject.domain.auth.dto.req;

public record LoginReqDTO (
        String email,
        String password,
        String deviceId
){
}
