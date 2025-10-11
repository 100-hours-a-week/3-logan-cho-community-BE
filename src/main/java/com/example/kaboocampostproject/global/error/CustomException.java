package com.example.kaboocampostproject.global.error;

import lombok.Getter;

@Getter
public class CustomException extends RuntimeException{
    BaseErrorCode errorCode;
    public CustomException(BaseErrorCode errorCode) {
        this.errorCode = errorCode;
    }
}
