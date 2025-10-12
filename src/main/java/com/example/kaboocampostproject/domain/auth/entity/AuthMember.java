package com.example.kaboocampostproject.domain.auth.entity;

import com.example.kaboocampostproject.domain.member.entity.Member;
import com.example.kaboocampostproject.domain.member.entity.UserRole;
import jakarta.persistence.*;
import lombok.*;

@Entity
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Getter
@Builder
@Table(name = "auth_member")
public class AuthMember {

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

    @Enumerated(EnumType.STRING)
    UserRole role;

    public void updatePassword(String password) {
        this.password = password;
    }
}
