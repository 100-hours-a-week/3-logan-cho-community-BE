package com.example.kaboocampostproject.domain.auth.service;

import com.example.kaboocampostproject.domain.auth.dto.req.LoginReqDTO;
import com.example.kaboocampostproject.domain.auth.entity.AuthMember;
import com.example.kaboocampostproject.domain.auth.repository.AuthMemberRepository;
import com.example.kaboocampostproject.domain.auth.session.SessionManager;
import com.example.kaboocampostproject.domain.member.dto.request.UpdateMemberReqDTO;
import com.example.kaboocampostproject.domain.member.error.MemberErrorCode;
import com.example.kaboocampostproject.domain.member.error.MemberException;
import com.example.kaboocampostproject.global.metadata.JwtMetadata;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseCookie;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;

import static com.example.kaboocampostproject.domain.auth.session.SessionFilter.SESSION_ID;

@RequiredArgsConstructor
@Service
public class AuthMemberService {
    private final AuthMemberRepository authMemberRepository;
    private final PasswordEncoder passwordEncoder;
    private final SessionManager sessionManager;


    @Transactional(readOnly = true)
    public void login(HttpServletResponse response, LoginReqDTO dto) {
        AuthMember authMember = authMemberRepository.findByEmail(dto.email()).orElseThrow(()->
                new MemberException(MemberErrorCode.PASSWORD_AND_EMAIL_NOT_MATCH)); // 이메일을 알아낼 수 없도록

        if (!passwordEncoder.matches(dto.password(), authMember.getPassword())) {
            throw new MemberException(MemberErrorCode.PASSWORD_AND_EMAIL_NOT_MATCH);
        }

        String sessionId = sessionManager.storeAuthentication(authMember.getId(), authMember.getRole());

        setCookie(response, sessionId);
    }

    private void setCookie(HttpServletResponse response, String sessionId) {
        ResponseCookie cookie = ResponseCookie.from(SESSION_ID, sessionId)
                .httpOnly(true)
                .secure(true)
                .sameSite("Strict")
                .path("/")
                .build();

        response.addHeader("Set-Cookie", cookie.toString());
    }
    public void logout(HttpServletResponse response) {
        // 세션 인증 삭제
        sessionManager.removeAuthentication(SESSION_ID);
        expireRefreshCookie(response);//쿠키 삭제
    }

    private void expireRefreshCookie(HttpServletResponse response) {
        ResponseCookie expired = ResponseCookie.from(JwtMetadata.REFRESH_JWT.getJwtType(), "")
                .httpOnly(true)
                .secure(true)
                .sameSite("Strict")
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

}
