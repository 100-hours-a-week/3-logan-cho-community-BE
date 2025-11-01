package com.example.kaboocampostproject.domain.auth.jwt.dto;

import lombok.Builder;

@Builder
public record IssuedJwts(
        String accessJwt,
        String refreshJwt
){
}
