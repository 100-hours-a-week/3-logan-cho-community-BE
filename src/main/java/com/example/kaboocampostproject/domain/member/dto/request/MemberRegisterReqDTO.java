package com.example.kaboocampostproject.domain.member.dto.request;


import com.example.kaboocampostproject.global.validator.annotation.ValidName;
import com.example.kaboocampostproject.global.validator.annotation.ValidPassword;
import com.mongodb.lang.Nullable;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import lombok.Builder;

@Builder
public record MemberRegisterReqDTO(
        @Email @NotBlank String email,
        @ValidPassword String password,
        @ValidName String name,
        @Nullable String imageObjectKey
) { }
