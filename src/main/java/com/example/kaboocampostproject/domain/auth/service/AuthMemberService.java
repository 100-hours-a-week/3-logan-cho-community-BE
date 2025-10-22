package com.example.kaboocampostproject.domain.auth.service;

import com.example.kaboocampostproject.domain.auth.dto.EmailCheckReqDTO;
import com.example.kaboocampostproject.domain.auth.dto.LoginReqDTO;
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

        String encodedPassword = passwordEncoder.encode(password.oldPassword());
        if (!passwordEncoder.matches(authMember.getPassword(), encodedPassword)) {
            throw new MemberException(MemberErrorCode.PASSWORD_NOT_MATCH);
        }
        authMember.updatePassword(encodedPassword);
    }

    public boolean isEmailDuplicate(EmailCheckReqDTO emailDto) {
        return authMemberRepository.existsByEmail(emailDto.email());
    }
}
