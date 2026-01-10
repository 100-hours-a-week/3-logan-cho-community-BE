package com.example.kaboocampostproject.domain.like.repository;


import com.example.kaboocampostproject.domain.like.dto.PostLikeStatsDto;
import com.example.kaboocampostproject.domain.like.entity.PostLike;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface PostLikeRepository extends JpaRepository<PostLike, Long> {

    @Query("""
        SELECT new com.example.kaboocampostproject.domain.like.dto.PostLikeStatsDto(
            pl.postId,
            COUNT(pl),
            MAX(CASE WHEN pl.memberId = :memberId THEN true ELSE false END)
        )
        FROM PostLike pl
        WHERE pl.postId IN :postIds
        GROUP BY pl.postId
    """)
    List<PostLikeStatsDto> findPostLikeStats(
            @Param("postIds") List<String> postIds,
            @Param("memberId") Long memberId
    );

    @Query("""
    SELECT new com.example.kaboocampostproject.domain.like.dto.PostLikeStatsDto(
        pl.postId,
        COUNT(pl),
        MAX(CASE WHEN pl.memberId = :memberId THEN true ELSE false END)
    )
    FROM PostLike pl
    WHERE pl.postId = :postId
    GROUP BY pl.postId
""")
    Optional<PostLikeStatsDto> findPostLikeStatsByPostId(
            @Param("postId") String postId,
            @Param("memberId") Long memberId
    );

    boolean existsByMemberIdAndPostId(Long memberId, String postId); //좋아요 여부

    PostLike findByMemberIdAndPostId(Long memberId, String postId);

    List<PostLike> findAllByMemberId(Long memberId);

    List<PostLike> findByMemberIdAndPostIdIn(Long memberId, List<String> postIds);

    @Modifying
    @Query("""
        UPDATE PostLike 
        SET deletedAt = CURRENT_TIMESTAMP 
        WHERE memberId = :memberId
        AND deletedAt is null
        """)
    void softDeleteAllByMemberId(@Param("memberId") Long memberId);
}
