package com.example.kaboocampostproject.domain.post.service;

import com.example.kaboocampostproject.domain.post.repository.PostMongoRepository;
import com.example.kaboocampostproject.global.metadata.RedisMetadata;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.util.Map;
import java.util.concurrent.*;

@Slf4j
@Service
@RequiredArgsConstructor
public class PostViewService {

    private final BlockingQueue<String> viewQueue = new LinkedBlockingQueue<>();
    private final Map<String, Long> viewMap = new ConcurrentHashMap<>();
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    private final PostMongoRepository postRepository;

    @PostConstruct
    public void initQueueConsumer() {
        executor.submit(() -> {
            try {
                while (true) {
                    String postId = viewQueue.take(); // 쟉업 빼서 viewMap에 삽입
                    viewMap.merge(postId, 1L, Long::sum);
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        });
    }

    // 요청 시 호출
    public void incrementViewCount(String postId) {
        viewQueue.offer(postId); // 큐에 작업 추가
    }

    @Scheduled(fixedRate = 60_000)
    public void flushToMongo() {
        if (viewMap.isEmpty()) return;

        Map<String, Long> snapshot = Map.copyOf(viewMap);
        viewMap.clear();

        snapshot.forEach((postId, count) -> {
            try {
                postRepository.incrementViews(postId, count);
                log.debug("postId :{} flush {}증가", postId, count);
            } catch (Exception e) {
                log.error("\"postId :{} flush 실패. {}증가 실패", postId, count, e);
            }
        });
    }

    @PreDestroy
    public void onShutdown() {
        log.info("어플리케이션 종료 전 조회수 flush");
        flushToMongo(); // 남은 조회수 저장
        executor.shutdownNow();
    }
}
