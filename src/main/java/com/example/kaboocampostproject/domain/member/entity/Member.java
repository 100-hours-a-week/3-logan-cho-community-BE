package com.example.kaboocampostproject.domain.member.entity;

import com.example.kaboocampostproject.domain.auth.entity.AuthMember;
import com.example.kaboocampostproject.global.entity.BaseTimeEntity;
import com.example.kaboocampostproject.domain.like.entity.PostLike;
import com.mongodb.lang.Nullable;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.SQLDelete;
import org.hibernate.annotations.Where;
import java.util.ArrayList;
import java.util.List;

@Entity
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Getter
@Table(name = "members")
@SQLDelete(sql = "UPDATE member SET deleted_at = NOW() WHERE id = ?")
@Where(clause = "deleted_at IS NULL")
public class Member extends BaseTimeEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(length = 10, nullable = false)
    private String name;

    @Column(length = 30)
    private String imageObjectKey;

    // cascadeType.ALL 하지 않은 이유 : member 소프트 딜리트시 AuthMember는 @SQLDelete 없어서 하드딜리트 가능
    @OneToOne(mappedBy = "member", cascade = CascadeType.PERSIST, fetch = FetchType.LAZY)
    private AuthMember authMember;

    // member 소프트딜리트 시, 게시물 좋아요도 소프트딜리트 처리 위해 양방향 매핑 추가
    @OneToMany(mappedBy = "member", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    private List<PostLike> postLikes = new ArrayList<>();

    public void updateName(String name) {
        this.name = name;
    }

    public void updateImageObjectKey(String imageObjectKey) {
        this.imageObjectKey = imageObjectKey;
    }

    @Builder
    public Member(String name, @Nullable String imageObjectKey) {
        this.name = name;
        this.imageObjectKey = imageObjectKey;
    }
    public void setAuthMember(AuthMember authMember) {
        this.authMember = authMember;
    }
}
