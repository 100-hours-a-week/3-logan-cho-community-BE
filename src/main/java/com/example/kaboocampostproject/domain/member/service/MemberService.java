package com.example.kaboocampostproject.domain.member.service;

import com.example.kaboocampostproject.domain.auth.entity.AuthMember;
import com.example.kaboocampostproject.domain.auth.repository.AuthMemberRepository;
import com.example.kaboocampostproject.domain.member.dto.request.UpdateMemberReqDTO;
import com.example.kaboocampostproject.domain.member.entity.Member;
import com.example.kaboocampostproject.domain.member.cache.MemberProfileCacheService;
import com.example.kaboocampostproject.domain.member.converter.MemberConverter;
import com.example.kaboocampostproject.domain.member.dto.request.MemberRegisterReqDTO;
import com.example.kaboocampostproject.domain.member.cache.MemberProfileCacheDTO;
import com.example.kaboocampostproject.domain.member.entity.UserRole;
import com.example.kaboocampostproject.domain.member.error.MemberErrorCode;
import com.example.kaboocampostproject.domain.member.error.MemberException;
import com.example.kaboocampostproject.domain.member.repository.MemberRepository;
import com.example.kaboocampostproject.domain.s3.service.S3Service;
import lombok.RequiredArgsConstructor;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
@Transactional
public class MemberService {
    private final MemberRepository memberRepository;
    private final MemberProfileCacheService memberProfileCacheService;
    private final PasswordEncoder passwordEncoder;
    private final AuthMemberRepository authMemberRepository;
    private final S3Service s3Service;

    public void createMember(MemberRegisterReqDTO memberDTO) {
        AuthMember authMember = authMemberRepository.findByEmail(memberDTO.email()).orElse(null);
        if (authMember != null) {
            throw new MemberException(MemberErrorCode.MEMBER_EMAIL_DUPLICATED);
        }
        String encodedPassword = passwordEncoder.encode(memberDTO.password());
        UserRole userRole = UserRole.ROLE_USER; // 우선 모두 기본 사용자.
        Member member = MemberConverter.toEntity(memberDTO, encodedPassword, userRole);

        // 프로필 이미지 있다면 검증하기
        if (member.getImageObjectKey() != null && !member.getImageObjectKey().isEmpty()) {
            s3Service.verifyS3Upload(member.getImageObjectKey());
        }

        memberRepository.save(member);
    }

    @Transactional(readOnly = true)
    public MemberProfileCacheDTO getMemberProfile(Long memberId) {
        MemberProfileCacheDTO profile = memberProfileCacheService.getProfile(memberId);
        if (profile == null) {
            throw new MemberException(MemberErrorCode.MEMBER_NOT_FOND);
        }
        return profile;
    }

    public void updateMemberName(Long memberId, UpdateMemberReqDTO.MemberName memberName) {
        Member member = memberRepository.findById(memberId).orElseThrow(() ->
                new MemberException(MemberErrorCode.MEMBER_NOT_FOND));
        member.updateName(memberName.name());
        memberProfileCacheService.cacheProfile(MemberConverter.toProfile(member));
    }

    public void updateMemberImage(Long memberId, UpdateMemberReqDTO.MemberProfileImage memberImageObjectKey) {
        Member member = memberRepository.findById(memberId).orElseThrow(() ->
                new MemberException(MemberErrorCode.MEMBER_NOT_FOND));

        // 업로드 검사
        s3Service.verifyS3Upload(member.getImageObjectKey());

        // 없었다면 추가
        member.updateImageObjectKey(memberImageObjectKey.imageObjectKey());
        memberProfileCacheService.cacheProfile(MemberConverter.toProfile(member));
    }

    // 소프트 딜리트
    public void deleteMember(Long memberId) {
        memberRepository.deleteById(memberId);
        memberProfileCacheService.removeProfileCached(memberId);
    }

}
