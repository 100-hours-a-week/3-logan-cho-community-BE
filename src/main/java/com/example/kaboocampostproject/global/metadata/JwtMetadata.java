package com.example.kaboocampostproject.global.metadata;

import lombok.AllArgsConstructor;
import lombok.Getter;

@Getter
@AllArgsConstructor
public enum JwtMetadata {

    ACCESS_JWT("ACCESS_JWT", 1800),//30분
    REFRESH_JWT("REFRESH_JWT", 360000),//100시간

    ;
    String jwtType;
    long ttlSeconds;

}
