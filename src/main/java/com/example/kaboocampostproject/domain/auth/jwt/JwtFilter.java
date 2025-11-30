package com.example.kaboocampostproject.domain.auth.jwt;

import com.example.kaboocampostproject.domain.auth.jwt.dto.AccessClaims;
import com.example.kaboocampostproject.domain.auth.jwt.exception.JwtErrorCode;
import com.example.kaboocampostproject.domain.auth.jwt.exception.JwtException;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
@Slf4j
@RequiredArgsConstructor
@Component
public class JwtFilter extends OncePerRequestFilter {

    private final JwtProvider jwtProvider;

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {

        String header = request.getHeader("Authorization");
        if (header != null && header.startsWith("Bearer ")) {
            String accessToken = header.substring(7);
            try {
                AccessClaims claims = jwtProvider.parseAndValidateAccess(accessToken);
                Authentication auth = jwtProvider.getAuthentication(claims);
                SecurityContextHolder.getContext().setAuthentication(auth);
                request.setAttribute("memberId", claims.userId());
            } catch (JwtException e) {
                SecurityContextHolder.clearContext();
                request.setAttribute("exception", e.getErrorCode());
            }
        } else {
            request.setAttribute("exception", JwtErrorCode.EMPTY_TOKEN);
        }
        filterChain.doFilter(request, response);

    }

}
