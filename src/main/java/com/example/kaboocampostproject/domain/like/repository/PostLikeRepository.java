package com.example.kaboocampostproject.domain.like.repository;


import com.example.kaboocampostproject.domain.like.dto.PostLikeStatsDto;
import com.example.kaboocampostproject.domain.like.entity.PostLike;
import com.example.kaboocampostproject.domain.like.entity.PostLikeId;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface PostLikeRepository extends JpaRepository<PostLike, PostLikeId> {

    @Query("""
        SELECT new com.example.kaboocampostproject.domain.like.dto.PostLikeStatsDto(
            pl.id.postId,
            COUNT(pl),
            MAX(CASE WHEN pl.member.id = :memberId THEN true ELSE false END)
        )
        FROM PostLike pl
        WHERE pl.id.postId IN :postIds
        GROUP BY pl.id.postId
    """)
    List<PostLikeStatsDto> findPostLikeStats(
            @Param("postIds") List<String> postIds,
            @Param("memberId") Long memberId
    );

    @Query("""
    SELECT new com.example.kaboocampostproject.domain.like.dto.PostLikeStatsDto(
        pl.id.postId,
        COUNT(pl),
        MAX(CASE WHEN pl.member.id = :memberId THEN true ELSE false END)
    )
    FROM PostLike pl
    WHERE pl.id.postId = :postId
    GROUP BY pl.id.postId
""")
    Optional<PostLikeStatsDto> findPostLikeStatsByPostId(
            @Param("postId") String postId,
            @Param("memberId") Long memberId
    );
}
