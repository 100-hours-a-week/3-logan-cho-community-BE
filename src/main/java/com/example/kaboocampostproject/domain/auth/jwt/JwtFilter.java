package com.example.kaboocampostproject.domain.auth.jwt;

import com.example.kaboocampostproject.domain.auth.jwt.dto.AccessClaims;
import com.example.kaboocampostproject.domain.auth.jwt.exception.JwtErrorCode;
import com.example.kaboocampostproject.domain.auth.jwt.exception.JwtException;
import com.example.kaboocampostproject.global.error.BaseErrorCode;
import com.example.kaboocampostproject.global.response.CustomResponse;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.util.AntPathMatcher;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.servlet.HandlerExceptionResolver;

import java.io.IOException;
import java.util.Arrays;
import java.util.List;

@RequiredArgsConstructor
@Component
public class JwtFilter extends OncePerRequestFilter {

    private final JwtProvider jwtProvider;
    private final ObjectMapper objectMapper = new ObjectMapper();
    private final AntPathMatcher pathMatcher = new AntPathMatcher();

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
            // AT추출, null체크
            String accessToken = extractJwtByHeader(request);

            AccessClaims claims = jwtProvider.parseAndValidateAccess(accessToken);
            request.setAttribute("memberId", claims.userId());

            filterChain.doFilter(request, response);
        }catch (JwtException e){
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

    private String extractJwtByHeader(HttpServletRequest request) {
        String header = request.getHeader("Authorization");
        if (header == null || !header.startsWith("Bearer ")) {
            throw new JwtException(JwtErrorCode.EMPTY_TOKEN);
        }
        return header.substring(7);
    }

}
