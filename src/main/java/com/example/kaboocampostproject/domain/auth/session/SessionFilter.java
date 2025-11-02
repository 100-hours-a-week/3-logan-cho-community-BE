package com.example.kaboocampostproject.domain.auth.session;

import com.example.kaboocampostproject.domain.auth.error.AuthMemberErrorCode;
import com.example.kaboocampostproject.domain.auth.error.AuthMemberException;
import com.example.kaboocampostproject.domain.auth.session.dto.UserAuthentication;
import com.example.kaboocampostproject.global.error.BaseErrorCode;
import com.example.kaboocampostproject.global.response.CustomResponse;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseCookie;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.util.AntPathMatcher;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;

@RequiredArgsConstructor
@Component
public class SessionFilter extends OncePerRequestFilter {

    private final SessionManager sessionManager;
    private final ObjectMapper objectMapper = new ObjectMapper();
    private final AntPathMatcher pathMatcher = new AntPathMatcher();

    public static final String SESSION_ID = "SESSIONID";
    private static final List<String> ALLOWING_URLS = List.of(
            //docs
            "/swagger-ui/**",
            "/swagger-resources/**",
            "/v3/api-docs/**",
            // ssr
            "/policy/**", "/css/**",
            // 허용 api
            "/api/auth"
    );

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) throws ServletException{
        boolean shouldNotFilter = ALLOWING_URLS.stream().anyMatch(pattern -> pathMatcher.match(pattern, request.getRequestURI()));
        if (request.getRequestURI().equals("/api/members") && request.getMethod().equals("POST")) { // 회원가입 요청
            shouldNotFilter = true;
        }
        return shouldNotFilter;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {

        try{
            // sessionId 추출, null체크
            String sessionId = extractSessionIdByCookie(request);

            UserAuthentication userAuthentication = sessionManager.verifyAuthentication(sessionId);
            request.setAttribute("memberId", userAuthentication.memberId());

            // 세션id 교체(tag만)
            setCookie(response, userAuthentication.sessionId());

            filterChain.doFilter(request, response);
        }catch (AuthMemberException e){
            BaseErrorCode errorCode = e.getErrorCode();
            CustomResponse<Void> errorResponse = CustomResponse.onFailure(errorCode.getCode(), errorCode.getMessage());

            // 응답 직접 작성 후 반환
            response.addHeader("Access-Control-Allow-Origin", "localhost:3000");
            response.setStatus(errorCode.getHttpStatus().value());
            response.setContentType("application/json;charset=UTF-8");
            response.getWriter().write(objectMapper.writeValueAsString(ResponseEntity
                    .status(errorCode.getHttpStatus())
                    .body(errorResponse)));
            return;
        }


    }

    private String extractSessionIdByCookie(HttpServletRequest request) {

        return Arrays.stream(Optional.ofNullable(request.getCookies()).orElseThrow(() ->
                        new AuthMemberException(AuthMemberErrorCode.EMPTY_SESSIONID_IN_COOKIE)))
                .filter(cookie -> SESSION_ID.equals(cookie.getName()))
                .map(Cookie::getValue)
                .findFirst()
                .orElseThrow(() -> new AuthMemberException(AuthMemberErrorCode.EMPTY_SESSIONID_IN_COOKIE));

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

}
