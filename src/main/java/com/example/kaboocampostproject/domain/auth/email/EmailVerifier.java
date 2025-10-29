package com.example.kaboocampostproject.domain.auth.email;

import com.example.kaboocampostproject.domain.auth.error.AuthMemberErrorCode;
import com.example.kaboocampostproject.domain.auth.error.AuthMemberException;
import com.example.kaboocampostproject.global.metadata.RedisMetadata;
import lombok.RequiredArgsConstructor;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import java.util.UUID;
import java.util.concurrent.TimeUnit;

@Component
@RequiredArgsConstructor
public class EmailVerifier {

    private final StringRedisTemplate redisTemplate;
    private final EmailSender emailSender;

    // 인증 코드 생성 -> redis 저장 -> 인증코드 발송
    public void sendVerificationEmail(String email, RedisMetadata emailVerificationCodeMeta) {
        // 랜덤 인증 코드 생성
        String verificationCode = generateRandomCode(6);
        int ttlMinutes = (int) emailVerificationCodeMeta.getTtl().toMinutes();

        // Redis 저장
        String redisKey = emailVerificationCodeMeta.keyOf(email);
        redisTemplate.opsForValue().set(redisKey, verificationCode, ttlMinutes, TimeUnit.MINUTES);

        // 이메일 발송
        emailSender.sendVerificationEmail(email, verificationCode, ttlMinutes);

    }

    // 이메일 코드 검증 -> UUID 토큰 발급
    public String verifyCodeAndIssueToken(String email, String inputCode, RedisMetadata emailVerificationCodeMeta, RedisMetadata emailVerifiedTokenMeta) {
        String redisKey = emailVerificationCodeMeta.keyOf(email);
        String cachedCode = redisTemplate.opsForValue().get(redisKey);

        if (!StringUtils.hasText(cachedCode) || !cachedCode.equals(inputCode)) {
            throw new AuthMemberException(AuthMemberErrorCode.INVALID_VERIFICATION_CODE);
        }

        redisTemplate.delete(redisKey);

        // UUID 기반 토큰 발급
        String emailVerifiedToken = UUID.randomUUID().toString();
        String tokenKey = emailVerifiedTokenMeta.keyOf(email);
        int ttlMinutes = (int) emailVerificationCodeMeta.getTtl().toMinutes();

        redisTemplate.opsForValue().set(tokenKey, emailVerifiedToken,
                ttlMinutes,
                TimeUnit.MINUTES);

        return emailVerifiedToken;
    }


    // 전달받은 토큰 검증
    public void validateToken(String email, String providedToken, RedisMetadata emailVerifiedTokenMeta) {
        String tokenKey = emailVerifiedTokenMeta.keyOf(email);
        String cachedToken = redisTemplate.opsForValue().get(tokenKey);

        if (!StringUtils.hasText(cachedToken) || !cachedToken.equals(providedToken)) {
            throw new AuthMemberException(AuthMemberErrorCode.INVALID_EMAIL_VERIFIED_TOKEN);
        }

        // 검증했으니 토큰 삭제
        redisTemplate.delete(tokenKey);
    }

    private String generateRandomCode(int length) {
        String chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        StringBuilder sb = new StringBuilder(length);
        for (int i = 0; i < length; i++) {
            int idx = (int) (Math.random() * chars.length());
            sb.append(chars.charAt(idx));
        }
        return sb.toString();
    }
    ///  첫 사용자 가입 플로우

    // (공통) 이메일 중복검사 -> 삭제된 사용자 확인 -> 이메일 전송 -> redis 캐싱

    // redis 검증 및 토큰 발급

    // 토큰과 함께 회원가입


    ///  탈퇴 후 재가입 사용자

    // 삭제된 사용자 확인 및 isLeavedMember=true 반환

    // 프론트에서 계정 복구하기 ui 띄우고 (이메일 그대로 가져가기) 다시 인증 버튼 클릭

    // 삭제 멤버여부 재 확인 및 인증코드 발송 -> redis 캐싱

    // redis 검증 후 jwt 발급 및 전송하기 (여기서 비번 바꾸는 선택지를 줄까말까)

}
