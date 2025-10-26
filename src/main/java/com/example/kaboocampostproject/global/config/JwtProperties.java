package com.example.kaboocampostproject.global.config;

import io.jsonwebtoken.security.Keys;
import lombok.Getter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;

@Configuration
@Getter
public class JwtProperties {
    // Base64 인코딩된 랜덤 시크릿(256비트 이상 권장)
    @Value("${auth.token.hmacSecretBase64}")
    private String hmacSecretBase64;

    @Bean
    public SecretKey jwtSecretKey() {
        return Keys.hmacShaKeyFor(hmacSecretBase64.getBytes(StandardCharsets.UTF_8));
    }

}
