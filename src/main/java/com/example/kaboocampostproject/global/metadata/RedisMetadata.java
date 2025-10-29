package com.example.kaboocampostproject.global.metadata;

import lombok.AllArgsConstructor;
import lombok.Getter;
import org.springframework.data.redis.connection.DataType;

import java.time.Duration;
import java.util.Arrays;
import java.util.stream.Collectors;

@Getter
@AllArgsConstructor
public enum RedisMetadata {

    MEMBER_PROFILE("PROFILE_CACHE:", DataType.STRING, Duration.ofHours(1)),
    POST_VIEW("POST_VIEW:", DataType.STRING, Duration.ofHours(1)),

    // 이메일 인증
    EMAIL_VERIFICATION("EMAIL_VERIFICATION:", DataType.STRING, Duration.ofMinutes(5)),
    EMAIL_VERIFIED_TOKEN("EMAIL_SIGNUP_TOKEN:", DataType.STRING, Duration.ofMinutes(10)),

    EMAIL_VERIFICATION_CODE_SIGNUP("EMAIL_VERIFICATION_CODE:SIGNUP:", DataType.STRING, Duration.ofMinutes(5)),
    EMAIL_VERIFIED_TOKEN_SIGNUP("EMAIL_VERIFIED_TOKEN:SIGNUP:", DataType.STRING, Duration.ofMinutes(10)),
    EMAIL_VERIFICATION_CODE_RECOVER("EMAIL_VERIFICATION_CODE:RECOVER:", DataType.STRING, Duration.ofMinutes(5)),
    EMAIL_VERIFIED_TOKEN_RECOVER("EMAIL_VERIFIED_TOKEN:RECOVER:", DataType.STRING, Duration.ofMinutes(10)),
    ;

    private final String prefix;
    private final DataType dataType; //레디스 자료구조
    private final Duration ttl;

    public String keyOf(Object... values) {
        return prefix + Arrays.stream(values)
                .map(Object::toString)
                .collect(Collectors.joining(":"));
    }
}

