package com.example.kaboocampostproject.domain.auth.repository;

import com.example.kaboocampostproject.domain.auth.entity.AuthMember;
import io.lettuce.core.dynamic.annotation.Param;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.Optional;

public interface AuthMemberRepository extends JpaRepository<AuthMember, Long> {

    Optional<AuthMember> findByMemberId(Long memberId);
    @Query(
            value = "SELECT * FROM auth_member WHERE email = :email",
            nativeQuery = true
    )
    AuthMember findByEmailWithDeleted(@Param("email") String email);

    Optional<AuthMember> findByEmail(String email);
    boolean existsByEmail(String email);
}
