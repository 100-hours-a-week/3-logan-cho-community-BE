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

    @Column(length = 255)
    private String imageObjectKey;


    @OneToOne(mappedBy = "member", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    private AuthMember authMember;

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
