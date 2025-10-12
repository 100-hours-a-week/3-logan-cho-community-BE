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

