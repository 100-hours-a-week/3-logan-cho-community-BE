package com.example.kaboocampostproject.global.error;


import lombok.AllArgsConstructor;
import lombok.Getter;
import org.springframework.http.HttpStatus;

@Getter
@AllArgsConstructor
public enum GeneralErrorCode implements BaseErrorCode {
    ACCESS_TOKEN_EXPIRED(HttpStatus.BAD_REQUEST, "JWT400_01" , "토큰이 만료되었습니다.")

    ;
    private HttpStatus httpStatus;
    private String code;
    private String message;
}
