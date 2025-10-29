package com.example.kaboocampostproject.domain.auth.dto.res;

import com.example.kaboocampostproject.domain.auth.jwt.dto.IssuedJwts;

public record AccessJwtResDTO(
        String accessJwt
) {
    public static AccessJwtResDTO buildAccessJwtResDTO(IssuedJwts issuedJwts) {
        return new AccessJwtResDTO(issuedJwts.accessJwt());
    }
}
