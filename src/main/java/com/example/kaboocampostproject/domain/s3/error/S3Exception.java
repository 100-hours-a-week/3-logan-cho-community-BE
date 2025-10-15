package com.example.kaboocampostproject.domain.s3.error;


import com.example.kaboocampostproject.global.error.CustomException;

public class S3Exception extends CustomException {
    public S3Exception(S3ErrorCode errorCode) {
        super(errorCode);
    }
}
