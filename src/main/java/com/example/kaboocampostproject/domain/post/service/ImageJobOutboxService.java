package com.example.kaboocampostproject.domain.post.service;

import com.example.kaboocampostproject.domain.post.config.ImagePipelineProperties;
import com.example.kaboocampostproject.domain.post.document.ImageJobOutboxDocument;
import com.example.kaboocampostproject.domain.post.document.PostDocument;
import com.example.kaboocampostproject.domain.post.dto.message.AsyncImageJobMessage;
import com.example.kaboocampostproject.domain.post.enums.ImageJobOutboxStatus;
import com.example.kaboocampostproject.domain.post.repository.ImageJobOutboxRepository;
import com.example.kaboocampostproject.domain.post.repository.PostMongoRepository;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.UUID;
import java.util.function.Function;

@Service
@RequiredArgsConstructor
public class ImageJobOutboxService {
    private static final long RELAY_LEASE_SECONDS = 30L;

    private final PostMongoRepository postRepository;
    private final ImageJobOutboxRepository outboxRepository;
    private final ImageJobPublisher imageJobPublisher;
    private final ObjectMapper objectMapper;
    private final ImagePipelineProperties imagePipelineProperties;
    private final String relayOwner = "relay-" + UUID.randomUUID();

    @Transactional("mongoTransactionManager")
    public void savePostWithOutbox(PostDocument post, Function<PostDocument, AsyncImageJobMessage> messageFactory) {
        postRepository.save(post);
        AsyncImageJobMessage message = messageFactory.apply(post);
        outboxRepository.save(
                ImageJobOutboxDocument.builder()
                        .imageJobId(message.imageJobId())
                        .postId(post.getId())
                        .status(ImageJobOutboxStatus.PENDING)
                        .payloadJson(writePayload(message))
                        .publishAttempts(0)
                        .lastError(null)
                        .nextAttemptAt(Instant.now())
                        .publishedAt(null)
                        .processingOwner(null)
                        .build()
        );
    }

    @Scheduled(fixedDelayString = "${image.pipeline.outbox.relay-fixed-delay-ms:1000}")
    public void relayPendingMessages() {
        if (!imagePipelineProperties.isAsyncEnabled()
                || !imagePipelineProperties.isOutboxEnabled()
                || !imagePipelineProperties.isOutboxRelayEnabled()) {
            return;
        }

        int batchSize = Math.max(1, imagePipelineProperties.getOutboxRelayBatchSize());
        for (int i = 0; i < batchSize; i++) {
            Instant now = Instant.now();
            ImageJobOutboxDocument document = outboxRepository
                    .claimNextRelayCandidate(now, now.plusSeconds(RELAY_LEASE_SECONDS), relayOwner)
                    .orElse(null);
            if (document == null) {
                break;
            }
            try {
                imageJobPublisher.publish(readPayload(document.getPayloadJson()));
                outboxRepository.completeRelayAttempt(document.getId(), relayOwner, true, null, null);
            } catch (RuntimeException e) {
                outboxRepository.completeRelayAttempt(
                        document.getId(),
                        relayOwner,
                        false,
                        nextAttemptAt(document),
                        trimError(e)
                );
            }
        }
    }

    private String writePayload(AsyncImageJobMessage message) {
        try {
            return objectMapper.writeValueAsString(message);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("failed to serialize async image job outbox payload", e);
        }
    }

    private AsyncImageJobMessage readPayload(String payloadJson) {
        try {
            return objectMapper.readValue(payloadJson, AsyncImageJobMessage.class);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("failed to deserialize async image job outbox payload", e);
        }
    }

    private Instant nextAttemptAt(ImageJobOutboxDocument document) {
        long delaySeconds = Math.min(30L, 2L + document.getPublishAttempts() * 2L);
        return Instant.now().plusSeconds(delaySeconds);
    }

    private String trimError(RuntimeException e) {
        String message = e.getMessage();
        if (message == null || message.isBlank()) {
            return e.getClass().getSimpleName();
        }
        return message.length() > 300 ? message.substring(0, 300) : message;
    }
}
