package com.example.kaboocampostproject.domain.like.dto;

public record PostLikeStatsDto(
        String postId,       // 게시물 ID
        Long likeCount,    // 좋아요 개수
        Boolean amILike  // 내가 좋아요했는지 여부
) {}
