package com.example.kaboocampostproject.domain.comment.error;

import com.example.kaboocampostproject.global.error.BaseErrorCode;
import com.example.kaboocampostproject.global.error.CustomException;

public class CommentException extends CustomException {
    public CommentException(BaseErrorCode errorCode) {
        super(errorCode);
    }
}
