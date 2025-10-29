package com.example.kaboocampostproject.domain.like.entity;

import com.example.kaboocampostproject.global.mongo.StringIdBinaryConverter;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.SQLDelete;
import org.hibernate.annotations.Where;
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.jpa.domain.support.AuditingEntityListener;

import java.time.LocalDateTime;

@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Entity
@Table(
        name = "post_likes",
        indexes = {
                @Index(name = "idx_post_likes_composite", columnList = "post_id, member_id, deleted_at"),
                @Index(name = "idx_post_likes_member", columnList = "member_id")
        },
        uniqueConstraints = {
                @UniqueConstraint(
                        name = "uk_member_post_active",// member가 게시물에 좋아요를 한번만 추가할 수 있음을 명시.
                        columnNames = {"member_id", "post_id", "deleted_at"}
                )
        }
)
@SQLDelete(sql = "UPDATE post_likes SET deleted_at = NOW() WHERE id = ?")
@Where(clause = "deleted_at IS NULL")
@EntityListeners(AuditingEntityListener.class)
public class PostLike {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "post_id", columnDefinition = "BINARY(12)", nullable = false)
    @Convert(converter = StringIdBinaryConverter.class)
    private String postId;

    @Column(name = "member_id", nullable = false)
    private Long memberId;

    @CreatedDate
    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "deleted_at")
    private LocalDateTime deletedAt;

    private PostLike(Long memberId, String postId) {
        this.memberId = memberId;
        this.postId = postId;
    }

    public static PostLike of(Long memberId, String postId) {
        return new PostLike(memberId, postId);
    }
}
