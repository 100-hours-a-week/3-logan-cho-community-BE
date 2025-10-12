package com.example.kaboocampostproject.domain.member.error;

import com.example.kaboocampostproject.global.error.CustomException;
import lombok.Getter;

@Getter
public class MemberException extends CustomException {
    public MemberException(MemberErrorCode memberErrorCode) {
        super(memberErrorCode);
    }
}
