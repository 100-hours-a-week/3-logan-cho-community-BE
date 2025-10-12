package com.example.kaboocampostproject.domain.auth.jwt;


import com.example.kaboocampostproject.domain.auth.jwt.exception.JwtErrorCode;
import com.example.kaboocampostproject.global.error.BaseErrorCode;
import com.example.kaboocampostproject.global.response.CustomResponse;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.web.access.AccessDeniedHandler;
import org.springframework.stereotype.Component;

import java.io.IOException;

@Slf4j
@Component
public class JwtAccessDeniedHandler implements AccessDeniedHandler {

    // 인가 관련 예외처리

    @Override
    public void handle(HttpServletRequest request, HttpServletResponse response, AccessDeniedException accessDeniedException) throws IOException, ServletException {
        log.warn("403 Forbidden - Access Denied: {}", accessDeniedException.getMessage());

        // ContentType header 설정
        response.setContentType("application/json; charset=UTF-8");
        response.setStatus(HttpServletResponse.SC_FORBIDDEN);

        BaseErrorCode errorCode = JwtErrorCode.ACCESS_DENIED;
        // 반환할 응답 만들기
        CustomResponse<Void> errorResponse = CustomResponse.onFailure(errorCode.getCode(),errorCode.getMessage());
        // 응답을 response에 작성
        ObjectMapper mapper = new ObjectMapper();
        mapper.writeValue(response.getOutputStream(), errorResponse);
    }
}