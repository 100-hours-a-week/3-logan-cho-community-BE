package com.example.kaboocampostproject.domain.member.dto.response;

public record MemberProfileAndEmailResDTO(
        Long memberId,
        String name,
        String imageObjectKey,
        String email
) {
}
