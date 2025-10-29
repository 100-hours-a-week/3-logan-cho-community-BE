package com.example.kaboocampostproject.domain.auth.service;

import com.example.kaboocampostproject.domain.auth.dto.req.SendEmailReqDTO;
import com.example.kaboocampostproject.domain.auth.dto.req.LoginReqDTO;
import com.example.kaboocampostproject.domain.auth.dto.res.SendEmailResDTO;
import com.example.kaboocampostproject.domain.auth.email.EmailVerifier;
import com.example.kaboocampostproject.domain.auth.error.AuthMemberErrorCode;
import com.example.kaboocampostproject.domain.auth.error.AuthMemberException;
import com.example.kaboocampostproject.domain.auth.jwt.JwtProvider;
import com.example.kaboocampostproject.domain.auth.jwt.dto.IssuedJwts;
import com.example.kaboocampostproject.domain.auth.entity.AuthMember;
import com.example.kaboocampostproject.domain.auth.jwt.dto.RefreshClaims;
import com.example.kaboocampostproject.domain.auth.jwt.dto.ReissueJwts;
import com.example.kaboocampostproject.domain.auth.repository.AuthMemberRepository;
import com.example.kaboocampostproject.domain.member.dto.request.UpdateMemberReqDTO;
import com.example.kaboocampostproject.domain.member.error.MemberErrorCode;
import com.example.kaboocampostproject.domain.member.error.MemberException;
import com.example.kaboocampostproject.global.metadata.JwtMetadata;
import com.example.kaboocampostproject.global.metadata.RedisMetadata;
import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseCookie;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.util.Arrays;
import java.util.Optional;

@RequiredArgsConstructor
@Service
public class AuthMemberService {
    private final AuthMemberRepository authMemberRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtProvider jwtProvider;
    private final EmailVerifier emailVerifier;

    private static final String REFRESH_COOKIE_PATH = "/api/auth";

    @Transactional(readOnly = true)
    public IssuedJwts login(LoginReqDTO dto) {
        AuthMember authMember = authMemberRepository.findByEmail(dto.email()).orElseThrow(()->
                new MemberException(MemberErrorCode.PASSWORD_AND_EMAIL_NOT_MATCH)); // 이메일을 알아낼 수 없도록

        if (!passwordEncoder.matches(dto.password(), authMember.getPassword())) {
            throw new MemberException(MemberErrorCode.PASSWORD_AND_EMAIL_NOT_MATCH);
        }
        return jwtProvider.issueJwts(authMember.getId(), authMember.getRole(), dto.deviceId(), null);
    }

    public ResponseCookie buildRefreshCookie(String refreshToken) {
        return ResponseCookie.from(JwtMetadata.REFRESH_JWT.getJwtType(), refreshToken)
                .httpOnly(true)
                .secure(true)
                .sameSite("Strict")
                .path(REFRESH_COOKIE_PATH)
                .maxAge(JwtMetadata.REFRESH_JWT.getTtlSeconds())
                .build();
    }

    public ReissueJwts reissueJwts(HttpServletRequest req) {
        String refreshJwt = extractRefreshFromCookie(req);
        RefreshClaims refreshClaims = jwtProvider.parseAndValidateRefresh(refreshJwt);

        String accessJwt = jwtProvider.buildAccessJwt(
                                refreshClaims.userId(),
                                refreshClaims.userRole());
        return new ReissueJwts(accessJwt);

    }
    // 쿠키에서 jwt 파싱
    private String extractRefreshFromCookie(HttpServletRequest req) {
        return Arrays.stream(Optional.ofNullable(req.getCookies()).orElse(new Cookie[0]))
                .filter(c -> JwtMetadata.REFRESH_JWT.getJwtType().equals(c.getName()))
                .map(Cookie::getValue)
                .findFirst()
                .orElse(null);
    }

    public void logout(HttpServletResponse response) {
        // 멱등성 보장 위해서 검증하지 않고 삭제
        expireRefreshCookie(response);//쿠키 삭제
    }

    private void expireRefreshCookie(HttpServletResponse response) {
        ResponseCookie expired = ResponseCookie.from(JwtMetadata.REFRESH_JWT.getJwtType(), "")
                .httpOnly(true)
                .secure(true)
                .sameSite("Strict")
                .path(REFRESH_COOKIE_PATH)
                .maxAge(Duration.ZERO)
                .build();
        response.addHeader("Set-Cookie", expired.toString());
    }

    @Transactional
    public void updatePassword(Long memberId, UpdateMemberReqDTO.MemberPassword password) {
        AuthMember authMember = authMemberRepository.findById(memberId).orElseThrow(()->
                new MemberException(MemberErrorCode.MEMBER_NOT_FOND));

        if (!passwordEncoder.matches(password.oldPassword(), authMember.getPassword())) {
            throw new MemberException(MemberErrorCode.PASSWORD_NOT_MATCH);
        }
        String encodedPassword = passwordEncoder.encode(password.newPassword());
        authMember.updatePassword(encodedPassword);
    }

    /// ================= 이메일 ==================
    public boolean isEmailDuplicate(SendEmailReqDTO emailDto) {

        return authMemberRepository.existsByEmail(emailDto.email());
    }

    // 이메일 전송 클릭 시 ->  중복검사 -> 재가입 여부확인 -> 이메일 인증번호 전송
    public SendEmailResDTO checkDuplicationAndSendEmail(SendEmailReqDTO sendEmailReqDTO) {

        AuthMember authMember = authMemberRepository.findByEmailWithDeleted(sendEmailReqDTO.email());
        if (authMember != null) {
            // 이메일 중복검사
            if(authMember.getDeletedAt() == null) throw new AuthMemberException(AuthMemberErrorCode.MEMBER_EMAIL_DUPLICATED);
            // 삭제된 멤버 알림
            return new SendEmailResDTO(true);
        }

        // 회원가입용 이메일 인증번호 전송
        emailVerifier.sendVerificationEmail(sendEmailReqDTO.email(), RedisMetadata.EMAIL_VERIFICATION_CODE_SIGNUP);

        return new SendEmailResDTO(false);
    }

    public void checkLeavedMemberAndSendEmail(SendEmailReqDTO sendEmailReqDTO) {
        AuthMember authMember = authMemberRepository.findByEmailWithDeleted(sendEmailReqDTO.email());
        if (authMember == null) {
            throw new MemberException(MemberErrorCode.MEMBER_NOT_FOND_BY_EMAIL);
        }else if (authMember.getDeletedAt() == null) {
            throw new AuthMemberException(AuthMemberErrorCode.INVALID_RECOVER_MEMBER);
        }
        // 회원 복구용 이메일 인증번호 전송
        emailVerifier.sendVerificationEmail(sendEmailReqDTO.email(), RedisMetadata.EMAIL_VERIFICATION_CODE_RECOVER);
    }
}
