package com.example.kaboocampostproject.domain.member.cache;

import com.example.kaboocampostproject.domain.member.repository.MemberRepository;
import com.example.kaboocampostproject.global.metadata.RedisMetadata;
import lombok.RequiredArgsConstructor;
import org.springframework.data.redis.core.RedisCallback;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.serializer.RedisSerializer;
import org.springframework.stereotype.Service;

import java.util.*;

@Service
@RequiredArgsConstructor
public class MemberProfileCacheService {
    private final RedisTemplate<String, MemberProfileCacheDTO> redisTemplate;
    private final MemberRepository memberRepository;

    public void cacheProfile(MemberProfileCacheDTO profile) {
        String key = RedisMetadata.MEMBER_PROFILE.keyOf(profile.id());
        redisTemplate.opsForValue().set(key, profile, RedisMetadata.MEMBER_PROFILE.getTtl());
    }

    public void removeProfileCached(Long memberId) {
        String key = RedisMetadata.MEMBER_PROFILE.keyOf(memberId);
        redisTemplate.delete(key);
    }

    // 없는 Member(소프트딜리트)는 null 반환
    public MemberProfileCacheDTO getProfile(Long memberId) {
        String key = RedisMetadata.MEMBER_PROFILE.keyOf(memberId);
        MemberProfileCacheDTO profile = redisTemplate.opsForValue().get(key);
        if (profile == null) {
            profile = memberRepository.getMemberProfile(memberId);
            if (profile != null) {
                cacheProfile(profile);
            }
        }
        return profile;
    }

    // 없는 Member(소프트딜리트)는 map에 미포함
    public Map<Long, MemberProfileCacheDTO> getProfiles(List<Long> memberIds) {
        if (memberIds == null || memberIds.isEmpty()) return Collections.emptyMap();

        RedisMetadata redisMeta = RedisMetadata.MEMBER_PROFILE;

        //중복제거
        List<Long> distinctMemberIds = memberIds.stream().distinct().toList();

        // redis에서 캐싱데이터 가져오기
        List<String> keys = distinctMemberIds.stream()
                .map(redisMeta::keyOf)
                .toList();

        List<MemberProfileCacheDTO> cached = redisTemplate.opsForValue().multiGet(keys);

        Map<Long, MemberProfileCacheDTO> result = new LinkedHashMap<>();
        List<Long> missed = new ArrayList<>();

        // 캐싱 데이터 넣고, 캐시미스 체크하기
        for (int i = 0; i < distinctMemberIds.size(); i++) {
            MemberProfileCacheDTO profileCached = cached.get(i);
            if (profileCached == null) missed.add(distinctMemberIds.get(i));
            else result.put(distinctMemberIds.get(i), profileCached);
        }

        if (!missed.isEmpty()) {
            // 캐시미스 DB 조회
            List<MemberProfileCacheDTO> profiles = memberRepository.getMemberProfiles(missed);

            // getValueSerializer()는 반환값이 RedisSerializer<?> 이기 때문에 타입 지정을 해 줘야 serialize(@Nullable T value) 사용가능
            RedisSerializer<MemberProfileCacheDTO> valueSerializer =
                    (RedisSerializer<MemberProfileCacheDTO>) redisTemplate.getValueSerializer();
            // 파이프라인으로 한번에 저장
            redisTemplate.executePipelined((RedisCallback<Object>) connection -> {
                for (MemberProfileCacheDTO dto : profiles) {
                    // RedisConnection은 저수준 명령어만 지원하므로 직접 직렬화 해줘야함.
                    String key = redisMeta.keyOf(dto.id());
                    byte[] k = redisTemplate.getStringSerializer().serialize(key);
                    byte[] v = valueSerializer.serialize(dto);
                    connection.stringCommands().setEx(k, redisMeta.getTtl().toSeconds(), v); // 명령어 큐잉
                }
                return null;
            });
            // 응답 결과에 병합
            profiles.forEach(dto -> result.put(dto.id(), dto));
        }

        return result;
    }

}
