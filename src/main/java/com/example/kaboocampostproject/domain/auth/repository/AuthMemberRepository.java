package com.example.kaboocampostproject.domain.auth.repository;

import com.example.kaboocampostproject.domain.auth.entity.AuthMember;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface AuthMemberRepository extends JpaRepository<AuthMember, Long> {

    Optional<AuthMember> findByMemberId(Long memberId);
    Optional<AuthMember> findByEmail(String email);
    boolean existsByEmail(String email);
}
