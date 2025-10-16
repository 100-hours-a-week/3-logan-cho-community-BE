package com.example.kaboocampostproject.domain.auth.jwt;


import com.example.kaboocampostproject.domain.auth.jwt.dto.AccessClaims;
import com.example.kaboocampostproject.domain.auth.jwt.dto.IssuedJwts;
import com.example.kaboocampostproject.domain.auth.jwt.dto.RefreshClaims;
import com.example.kaboocampostproject.domain.auth.jwt.exception.JwtErrorCode;
import com.example.kaboocampostproject.domain.auth.jwt.exception.JwtException;
import com.example.kaboocampostproject.domain.member.entity.UserRole;
import com.example.kaboocampostproject.global.metadata.JwtMetadata;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.ExpiredJwtException;
import io.jsonwebtoken.Jwts;
import jakarta.annotation.Nullable;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.time.Instant;
import java.util.Date;
import java.util.UUID;

@Slf4j
@Component
@RequiredArgsConstructor
public class JwtProvider {

    private final SecretKey signingKey;

    private static final String JWT_TYPE = "typ";
    private static final String ROLE = "role";
    private static final String DEVICE_ID = "did";
    private static final String REFRESH_VERSION = "ver";

    // Claim 추출
    private Claims parse(String jwt) {
        try {
            return Jwts.parser()
                    .verifyWith(signingKey)
                    .build()
                    .parseSignedClaims(jwt)
                    .getPayload();
        } catch (ExpiredJwtException e) {
            throw new JwtException(JwtErrorCode.EXPIRED_TOKEN);
        } catch (JwtException e) {
            throw e;
        } catch (Exception e) {
            throw new JwtException(JwtErrorCode.INVALID_TOKEN);
        }
    }

    public AccessClaims parseAndValidateAccess(String accessJwt) {

        Claims c = parse(accessJwt);

        // access 여부 체크
        String jwtType = c.get(JWT_TYPE, String.class);
        if (!jwtType.equals(JwtMetadata.ACCESS_JWT.getJwtType())) {
            throw new JwtException(JwtErrorCode.TOKEN_TYPE_MISMATCH);
        }

        Long userId = Long.parseLong(c.getSubject()); // userId 문자열
        UserRole userRole = UserRole.valueOf(c.get(ROLE, String.class));

        if (userId == 0L) {
            throw new JwtException(JwtErrorCode.MISSING_CLAIMS);
        }

        return new AccessClaims(userId, userRole);
    }

    public RefreshClaims parseAndValidateRefresh(String refreshJwt) {

        Claims c = parse(refreshJwt);

        // refresh 여부 체크
        String jwtType = c.get(JWT_TYPE, String.class);
        if (!jwtType.equals(JwtMetadata.REFRESH_JWT.getJwtType())) {
            throw new JwtException(JwtErrorCode.TOKEN_TYPE_MISMATCH);
        }

        Date exp = c.getExpiration();

        Long userId = Long.parseLong(c.getSubject()); // userId 문자열
        String deviceId = c.get(DEVICE_ID, String.class);
        UserRole userRole = UserRole.valueOf(c.get(ROLE, String.class));
        String refreshVersion = c.get(REFRESH_VERSION, String.class);

        if (userId == 0L || deviceId == null || refreshVersion == null) {
            throw new JwtException(JwtErrorCode.MISSING_CLAIMS);
        }

        return new RefreshClaims(userId, userRole, deviceId, refreshVersion, exp.toInstant());
    }


    public IssuedJwts issueJwts(Long userId, UserRole userRole, String deviceId, @Nullable Instant issuedAt) {

        String accessJwt = buildAccessJwt(userId, userRole);
        String refreshJwt = buildRefreshJwt(userId, userRole, deviceId, null, issuedAt);

        return IssuedJwts.builder()
                .accessJwt(accessJwt)
                .refreshJwt(refreshJwt)
                .build();
    }

    public String buildAccessJwt(Long userId, UserRole userRole) {

        Instant now = Instant.now();
        Instant expiration = now.plusSeconds(JwtMetadata.ACCESS_JWT.getTtlSeconds());

        return Jwts.builder()
                .subject(Long.toString(userId))
                .issuedAt(Date.from(now))
                .expiration(Date.from(expiration))
                .claim(JWT_TYPE, JwtMetadata.ACCESS_JWT.getJwtType())
                .claim(ROLE, userRole)
                .signWith(signingKey, Jwts.SIG.HS256)
                .compact();
    }

    public String buildRefreshJwt(Long userId, UserRole userRole, String deviceId, @Nullable String refreshVersion, @Nullable Instant issuedAt) {

        Instant now = (issuedAt != null) ? issuedAt : Instant.now(); // 재 발급 or 첫 발급
        Instant expiration = now.plusSeconds(JwtMetadata.REFRESH_JWT.getTtlSeconds());

        // 리프레시 토큰용 발급 로직
        return Jwts.builder()
                .subject(Long.toString(userId))
                .issuedAt(Date.from(now))
                .expiration(Date.from(expiration))
                .claim(JWT_TYPE, JwtMetadata.REFRESH_JWT.getJwtType())
                .claim(ROLE, userRole)
                .claim(DEVICE_ID, deviceId)
                .claim(REFRESH_VERSION, (refreshVersion==null)? UUID.randomUUID().toString(): refreshVersion)
                .signWith(signingKey, Jwts.SIG.HS256)
                .compact();

    }

    public Long getMemberId(String token) {
        Claims c = parse(token);
        String sub = c.getSubject();
        try {
            return Long.parseLong(sub);
        } catch (NumberFormatException e) {
            throw new JwtException(JwtErrorCode.ID_PARSE_FAIL);
        }
    }

    public Authentication getAuthentication(String accessJwt) {
        AccessClaims accessClaims = parseAndValidateAccess(accessJwt);
        UserDetails userDetails = new PrincipalDetails(accessClaims);
        return new UsernamePasswordAuthenticationToken(userDetails, null, userDetails.getAuthorities());
    }

}