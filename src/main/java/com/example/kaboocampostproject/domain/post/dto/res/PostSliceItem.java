package com.example.kaboocampostproject.domain.post.dto.res;

import com.example.kaboocampostproject.domain.like.dto.PostLikeStatsDto;
import com.example.kaboocampostproject.domain.member.cache.MemberProfileCacheDTO;
import lombok.Builder;

import java.time.Instant;

@Builder
public record PostSliceItem(
        String postId,
        String title,
        long views,
        Instant createdAt,
        AuthorProfile author,
        LikeInfo like
) {
    // 작성자 프로필
    @Builder
    public record AuthorProfile(Long id, String name, String profileImageUrl) {}
    //좋아요 정보
    @Builder
    public record LikeInfo(long count, boolean amILike) {}
}