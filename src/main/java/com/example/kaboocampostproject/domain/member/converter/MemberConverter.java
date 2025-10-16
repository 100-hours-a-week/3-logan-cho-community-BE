package com.example.kaboocampostproject.domain.member.converter;

import com.example.kaboocampostproject.domain.auth.entity.AuthMember;
import com.example.kaboocampostproject.domain.member.entity.Member;
import com.example.kaboocampostproject.domain.member.cache.MemberProfileCacheDTO;
import com.example.kaboocampostproject.domain.member.dto.request.MemberRegisterReqDTO;
import com.example.kaboocampostproject.domain.member.entity.UserRole;

public class MemberConverter {
    public static Member toEntity(MemberRegisterReqDTO dto, String encodedPassword, UserRole userRole) {
        Member member = Member.builder()
                .name(dto.name())
                .imageObjectKey(dto.imageObjectKey())
                .build();

        AuthMember authMember = AuthMember.builder()
                .email(dto.email())
                .password(encodedPassword)
                .role(userRole)
                .member(member)
                .build();

        member.setAuthMember(authMember);// 양방향 세팅을 위해서 authMember엔 member_id 가 필요

        return member;
    }

    public static MemberProfileCacheDTO toProfile(Member member) {
        return MemberProfileCacheDTO.builder()
                .id(member.getId())
                .name(member.getName())
                .profileImageObjectKey(member.getImageObjectKey())
                .build();
    }
}
