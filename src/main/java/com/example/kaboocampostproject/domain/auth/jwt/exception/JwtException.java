package com.example.kaboocampostproject.domain.auth.jwt.exception;

import com.example.kaboocampostproject.global.error.BaseErrorCode;
import lombok.Getter;

@Getter
public class JwtException extends RuntimeException{
    BaseErrorCode errorCode;
    public JwtException(BaseErrorCode errorCode) {
        this.errorCode = errorCode;
    }
}


