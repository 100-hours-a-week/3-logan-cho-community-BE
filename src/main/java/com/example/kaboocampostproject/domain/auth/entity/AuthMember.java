package com.example.kaboocampostproject.domain.auth.entity;

import com.example.kaboocampostproject.domain.member.entity.Member;
import com.example.kaboocampostproject.domain.member.entity.UserRole;
import com.example.kaboocampostproject.global.entity.BaseTimeEntity;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.SQLDelete;
import org.hibernate.annotations.Where;

@Entity
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Getter
@Builder
@Table(name = "auth_member")
@SQLDelete(sql = "UPDATE auth_member SET deleted_at = NOW() WHERE member_id = ?")
@Where(clause = "deleted_at IS NULL")
public class AuthMember extends BaseTimeEntity {

    @Id
    @Column(name = "member_id")
    private Long id;

    @MapsId //부모 키와 동일한 id 사용
    @OneToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "member_id")
    @Setter
    private Member member;

    @Column(length = 40, nullable = false, unique = true)
    private String email;

    @Column(length = 100, nullable = false)
    private String password;
    // 최근 비밀번호 변경시간 컬럼 추가
    // 과거 비밀번호도 별도 테이블 분리 저장 oldPassword( password, createdAt )

    @Enumerated(EnumType.STRING)
    UserRole role;

    public void updatePassword(String password) {
        this.password = password;
    }
    public void recoverAuthMember() {
        this.deletedAt = null;
    }
}
