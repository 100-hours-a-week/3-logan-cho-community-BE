package com.example.kaboocampostproject.domain.member.cache;

import lombok.Builder;

@Builder
public record MemberProfileCacheDTO(
        Long id,
        String name,
        String profileImageUrl
) {
}
