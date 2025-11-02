package com.example.kaboocampostproject.domain.auth.session;

import com.example.kaboocampostproject.domain.auth.error.AuthMemberErrorCode;
import com.example.kaboocampostproject.domain.auth.error.AuthMemberException;
import com.example.kaboocampostproject.domain.auth.session.dto.ParsedSessionId;
import com.example.kaboocampostproject.domain.auth.session.dto.UserAuthentication;
import com.example.kaboocampostproject.domain.member.entity.UserRole;
import com.example.kaboocampostproject.global.metadata.RedisMetadata;
import lombok.RequiredArgsConstructor;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

@Component
@RequiredArgsConstructor
public class SessionManager {
    private final StringRedisTemplate redisTemplate;

    private final static String TAG = "tag";
    private final static String MEMBER_ID = "mid";
    private final static String MEMBER_ROLE = "role";

    private final static RedisMetadata meta = RedisMetadata.LOGIN_SESSION;


    // 로그인
    public String storeAuthentication(Long memberId, UserRole role) {

        Map<String, Object> map = new HashMap<>();

        String sessionKey = UUID.randomUUID().toString();
        String redisKey = meta.keyOf(sessionKey);

        String tag = generateTag();

        // 정보 저장
        map.put(TAG, tag);
        map.put(MEMBER_ID, memberId.toString());
        map.put(MEMBER_ROLE, role.name());

        redisTemplate.opsForHash().putAll(redisKey, map);
        redisTemplate.expire(redisKey, meta.getTtl());

        return sessionKey + "." + tag;
    }

    private String generateTag() {
        return UUID.randomUUID().toString().replace("-", "").substring(0, 12);
    }

    // 세션 아이디 파싱
    private ParsedSessionId parseSessionId(String sessionId) {
        int dot = sessionId.indexOf('.');
        if (dot < 0) {
            throw new AuthMemberException(AuthMemberErrorCode.INVALID_SESSION_ID);
        }
        String sessionKey = sessionId.substring(0, dot);
        String tag = sessionId.substring(dot + 1);
        return new ParsedSessionId(sessionKey, tag);
    }

    // 인증 -> 인가정보 반환
    public UserAuthentication verifyAuthentication(String sessionId) {
        // 세션정보 꺼내기
        ParsedSessionId  parsedSessionId = parseSessionId(sessionId);
        String redisKey = meta.keyOf(parsedSessionId.sessionKey());

        Map<Object, Object> memberSessionMap = redisTemplate.opsForHash().entries(redisKey);
        if (memberSessionMap.isEmpty()) {
            throw new AuthMemberException(AuthMemberErrorCode.LOGIN_SESSION_NOT_FOUND);
        }

        // 널 체크
        String stringMemberId = memberSessionMap.get(MEMBER_ID).toString();
        String stringRole = memberSessionMap.get(MEMBER_ROLE).toString();
        String stringTag = memberSessionMap.get(TAG).toString();

        if (stringMemberId==null || stringRole==null || stringTag==null) {
            throw new AuthMemberException(AuthMemberErrorCode.LOGIN_SESSION_NOT_FOUND);
        }

        // 테그 검증
        if (!memberSessionMap.get(TAG).equals(parsedSessionId.tag())) {
            // 세션 블랙리스트
            redisTemplate.delete(redisKey);
            throw new AuthMemberException(AuthMemberErrorCode.SESSION_BLACKLISTED);
        }

        // 테그 회전
        String newTag = generateTag();
        redisTemplate.opsForHash().put(redisKey, TAG, newTag);
        // 세션아이디 생성
        String newSessionId = parsedSessionId.sessionKey() + "." + newTag;


        Long memberId = Long.parseLong(stringMemberId);
        UserRole role = UserRole.of(stringRole);

        return UserAuthentication.of(newSessionId, memberId, role);

    }

    // 로그아웃
    public void removeAuthentication(String sessionId) {
        ParsedSessionId  parsedSessionId = parseSessionId(sessionId);
        String redisKey = meta.keyOf(parsedSessionId.sessionKey());
        redisTemplate.delete(redisKey);
    }
}
