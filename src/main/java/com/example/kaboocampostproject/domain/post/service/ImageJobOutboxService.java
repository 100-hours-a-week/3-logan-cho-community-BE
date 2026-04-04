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
import java.util.List;
import java.util.function.Function;

@Service
@RequiredArgsConstructor
public class ImageJobOutboxService {

    private final PostMongoRepository postRepository;
    private final ImageJobOutboxRepository outboxRepository;
    private final ImageJobPublisher imageJobPublisher;
    private final ObjectMapper objectMapper;
    private final ImagePipelineProperties imagePipelineProperties;

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

        List<ImageJobOutboxDocument> pending = outboxRepository
                .findTop100ByStatusAndNextAttemptAtLessThanEqualOrderByCreatedAtAsc(
                        ImageJobOutboxStatus.PENDING,
                        Instant.now()
                );

        int batchSize = Math.max(1, imagePipelineProperties.getOutboxRelayBatchSize());
        for (ImageJobOutboxDocument document : pending.stream().limit(batchSize).toList()) {
            try {
                imageJobPublisher.publish(readPayload(document.getPayloadJson()));
                document.markPublished(Instant.now());
            } catch (RuntimeException e) {
                document.markRetryScheduled(nextAttemptAt(document), trimError(e));
            }
            outboxRepository.save(document);
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
