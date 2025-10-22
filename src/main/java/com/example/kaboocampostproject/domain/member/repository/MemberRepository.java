package com.example.kaboocampostproject.domain.member.repository;

import com.example.kaboocampostproject.domain.member.dto.response.MemberProfileAndEmailResDTO;
import com.example.kaboocampostproject.domain.member.entity.Member;
import com.example.kaboocampostproject.domain.member.cache.MemberProfileCacheDTO;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface MemberRepository extends JpaRepository<Member, Long> {

    @Query("""
        SELECT new com.example.kaboocampostproject.domain.member.cache.MemberProfileCacheDTO(
            m.id, m.name, m.imageObjectKey
        )
        FROM Member m
        WHERE m.id = :memberId
    """)
    MemberProfileCacheDTO getMemberProfile(@Param("memberId") Long memberIds);

    @Query("""
        SELECT new com.example.kaboocampostproject.domain.member.cache.MemberProfileCacheDTO(
            m.id, m.name, m.imageObjectKey
        )
        FROM Member m
        WHERE m.id IN :memberIds
    """)
    List<MemberProfileCacheDTO> getMemberProfiles(@Param("memberIds") List<Long> memberIds);


    @Query("""
        SELECT new com.example.kaboocampostproject.domain.member.dto.response.MemberProfileAndEmailResDTO(
                m.id, m.name, m.imageObjectKey, am.email
                )
        FROM Member m
        INNER JOIN AuthMember am
        ON m.id=am.id
        WHERE m.id=:memberId
        """)
    Optional<MemberProfileAndEmailResDTO> getMemberProfileAndEmail(@Param("memberId") Long memberId);

}
