package com.example.kaboocampostproject.domain.auth.jwt;


import com.example.kaboocampostproject.domain.auth.jwt.exception.JwtErrorCode;
import com.example.kaboocampostproject.global.response.CustomResponse;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.stereotype.Component;

import java.io.IOException;

@Component
@Slf4j
public class JwtAuthenticationEntryPoint implements AuthenticationEntryPoint {

    // 인증 관련 예외처리

    @Override
    public void commence(HttpServletRequest request, HttpServletResponse response, AuthenticationException authException) throws IOException, ServletException {
        response.setContentType("application/json; charset=UTF-8");
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);

        // JwtFilter에서 넣어준 예외코드
        Object exception = request.getAttribute("exception");


        JwtErrorCode errorCode = JwtErrorCode.EMPTY_TOKEN;
        if (exception instanceof JwtErrorCode) {//JwtErrorCode 객체 아니면 setAttribute 안한 경우니까 emptyToken
            errorCode = (JwtErrorCode) exception;
        }

        CustomResponse<Void> errorResponse = CustomResponse.onFailure(errorCode.getCode(),errorCode.getMessage());

        log.warn("jwtFilterFail: {} - {}", errorCode.getCode(), errorCode.getMessage());
        new ObjectMapper().writeValue(response.getOutputStream(), errorResponse);
    }
}