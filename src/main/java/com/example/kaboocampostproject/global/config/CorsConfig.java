package com.example.kaboocampostproject.global.config;

import lombok.RequiredArgsConstructor;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.List;

@Configuration
@RequiredArgsConstructor
@EnableConfigurationProperties(CorsProperties.class)
public class CorsConfig {//cross-origin 응답을 JS에서 읽을 수 있는지 통제
    private final CorsProperties corsProperties;

    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();

        // 공통 베이스 설정
        CorsConfiguration base = new CorsConfiguration();
        base.setAllowedOriginPatterns(corsProperties.getAllowedOriginPatterns());
        base.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"));
        base.setAllowedHeaders(List.of("*"));
        base.setMaxAge(3600L);

        // 쿠키 허용 경로
        CorsConfiguration cred = new CorsConfiguration(base);
        cred.setAllowCredentials(true);

        if (corsProperties.getCredPaths() != null) {
            for (String path : corsProperties.getCredPaths()) {
                source.registerCorsConfiguration(path, cred);
            }
        }

        // 쿠키 불필요 경로
        CorsConfiguration nonCred = new CorsConfiguration(base);
        nonCred.setAllowCredentials(false);
        source.registerCorsConfiguration("/api/**", nonCred);

        return source;
    }
}
