package com.example.kaboocampostproject.domain.auth.error;

import com.example.kaboocampostproject.global.error.BaseErrorCode;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;

@RequiredArgsConstructor
@Getter
public enum AuthMemberErrorCode implements BaseErrorCode {

    // 이메일 인증
    MEMBER_EMAIL_DUPLICATED(HttpStatus.BAD_REQUEST, "AUTHMEMBER_401_01", "이메일이 중복되었습니다"),
    INVALID_VERIFICATION_CODE(HttpStatus.BAD_REQUEST, "AUTHMEMBER_401_02", "인증 코드가 올바르지 않거나 만료되었습니다"),
    INVALID_EMAIL_VERIFIED_TOKEN(HttpStatus.BAD_REQUEST, "AUTHMEMBER_401_03", "이메일 인증 토큰이 유효하지 않거나 만료되었습니다"),

    // 회원 복구
    INVALID_RECOVER_MEMBER(HttpStatus.BAD_REQUEST, "AUTHMEMBER_401_04", "삭제된 멤버가 아닙니다.")
    ;

    private final HttpStatus httpStatus;
    private final String code;
    private final String message;
}
