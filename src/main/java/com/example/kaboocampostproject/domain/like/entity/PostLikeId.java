package com.example.kaboocampostproject.domain.like.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;
import lombok.*;

import java.io.Serializable;

@Getter
@NoArgsConstructor
@AllArgsConstructor
@Builder
@EqualsAndHashCode
@Embeddable
public class PostLikeId implements Serializable {

    @Column(name = "post_id")
    private String postId;

    @Column(name = "member_id")
    private Long memberId;
}
