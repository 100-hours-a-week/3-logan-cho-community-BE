package com.example.kaboocampostproject.domain.like.entity;

import com.example.kaboocampostproject.domain.member.entity.Member;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.SQLDelete;
import org.hibernate.annotations.Where;
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.jpa.domain.support.AuditingEntityListener;

import java.time.LocalDateTime;

@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
@Entity
@Table(
        name = "post_likes",
        indexes = {
                @Index(name = "idx_post_likes_post_id", columnList = "post_id"),//게시물 좋아요 개수조회
                @Index(name = "idx_post_likes_member_post", columnList = "member_id, post_id") //내가 좋아요했는지
        }
)
@SQLDelete(sql = "UPDATE likes SET deleted_at = NOW() WHERE id = ?")
@Where(clause = "deleted_at IS NULL")
@EntityListeners(AuditingEntityListener.class)
public class PostLike {

    @EmbeddedId
    private PostLikeId id;

    @MapsId("memberId")
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "member_id", nullable = false)
    private Member member;

    @CreatedDate
    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "deleted_at")
    protected LocalDateTime deletedAt;

}
