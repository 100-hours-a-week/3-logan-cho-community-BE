package com.example.kaboocampostproject.domain.member.dto.request;

import com.example.kaboocampostproject.global.validator.annotation.ValidName;
import com.example.kaboocampostproject.global.validator.annotation.ValidPassword;

public class UpdateMemberReqDTO {
    public record MemberPassword (
            @ValidPassword String oldPassword,
            @ValidPassword String newPassword
    )
    { }
    public record MemberName (
            @ValidName String name
    ){}
    public record MemberProfileImage (
            String imageObjectKey
    ){}
}
