package com.example.kaboocampostproject.global.error;

import com.example.kaboocampostproject.global.response.CustomResponse;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(CustomException.class)
    public ResponseEntity<CustomResponse<Void>> customExceptionHandler(CustomException customException){

        BaseErrorCode errorCode = customException.getErrorCode();

        return ResponseEntity.status(errorCode.getHttpStatus())
                .body(CustomResponse.onFailure(errorCode.getCode(), errorCode.getMessage()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<CustomResponse<Void>> customExceptionHandler(Exception exception){
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(CustomResponse.onFailure("500", "서버 내부 오류가 발생했습니다."));
    }
}
