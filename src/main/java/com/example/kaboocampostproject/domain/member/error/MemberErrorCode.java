package com.example.kaboocampostproject.domain.member.error;

import com.example.kaboocampostproject.global.error.BaseErrorCode;
import lombok.AllArgsConstructor;
import lombok.Getter;
import org.springframework.http.HttpStatus;

@Getter
@AllArgsConstructor
public enum MemberErrorCode implements BaseErrorCode{
    MEMBER_NOT_FOND(HttpStatus.NOT_FOUND, "MEMBER_404_01", "존재하지 않는 사용자입니다."),
    MEMBER_NOT_FOND_BY_EMAIL(HttpStatus.NOT_FOUND, "MEMBER_404_02", "해당 이메일에 일치하는 사용자가 없습니다."),
    PASSWORD_AND_EMAIL_NOT_MATCH(HttpStatus.NOT_FOUND, "MEMBER_404_03", "이메일, 또는 비밀번호가 잘못되었습니다."),

    //인가
    PASSWORD_NOT_MATCH(HttpStatus.FORBIDDEN, "MEMBER_403_02", "비밀번호가 잘못되었습니다."),

    MEMBER_EMAIL_DUPLICATED(HttpStatus.BAD_REQUEST, "MEMBER_401_01", "중복된 이메일입니다"),
    ;

    private final HttpStatus httpStatus;
    private final String code;
    private final String message;
}
