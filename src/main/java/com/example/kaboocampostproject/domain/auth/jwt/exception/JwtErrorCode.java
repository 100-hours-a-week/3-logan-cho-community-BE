package com.example.kaboocampostproject.domain.auth.jwt.exception;


import com.example.kaboocampostproject.global.error.BaseErrorCode;
import lombok.AllArgsConstructor;
import lombok.Getter;
import org.springframework.http.HttpStatus;

@Getter
@AllArgsConstructor
public enum JwtErrorCode implements BaseErrorCode {

    INVALID_TOKEN(HttpStatus.UNAUTHORIZED, "JWT403_01", "유효하지 않은 토큰입니다."),
    EXPIRED_TOKEN(HttpStatus.UNAUTHORIZED, "JWT403_02", "만료된 토큰입니다."),
    ACCESS_DENIED(HttpStatus.FORBIDDEN, "JWT403_03", "접근 권한이 없습니다."),

    EMPTY_TOKEN(HttpStatus.UNAUTHORIZED, "JWT401_01", "토큰이 비어있습니다."),
    TOKEN_TYPE_MISMATCH(HttpStatus.UNAUTHORIZED, "JWT401_02", "토큰 타입이 올바르지 않습니다."),
    MISSING_CLAIMS(HttpStatus.UNAUTHORIZED, "JWT401_03", "필수 클레임이 누락되었습니다."),
    ID_PARSE_FAIL(HttpStatus.UNAUTHORIZED, "JWT401_04", "아이디 파싱 실패"),

    ;

    private final HttpStatus httpStatus;
    private final String code;
    private final String message;
}
