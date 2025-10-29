package com.example.kaboocampostproject.domain.auth.error;

import com.example.kaboocampostproject.global.error.CustomException;

public class AuthMemberException extends CustomException {
    public AuthMemberException(AuthMemberErrorCode errorCode) {
        super(errorCode);
    }
}
