package com.example.kaboocampostproject.domain.post.error;

import com.example.kaboocampostproject.global.error.BaseErrorCode;
import com.example.kaboocampostproject.global.error.CustomException;

public class PostException extends CustomException {
    public PostException(BaseErrorCode errorCode) {
        super(errorCode);
    }
}
