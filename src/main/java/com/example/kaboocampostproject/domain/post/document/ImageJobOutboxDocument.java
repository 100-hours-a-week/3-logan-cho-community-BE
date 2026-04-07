package com.example.kaboocampostproject.domain.post.document;

import com.example.kaboocampostproject.domain.post.enums.ImageJobOutboxStatus;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.annotation.Id;
import org.springframework.data.annotation.LastModifiedDate;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

import java.time.Instant;

@Document(collection = "image_job_outbox")
@Getter
@NoArgsConstructor
public class ImageJobOutboxDocument {

    @Id
    private String id;

    @Indexed(unique = true)
    private String imageJobId;

    @Indexed
    private String postId;

    @Indexed
    private ImageJobOutboxStatus status;

    private String payloadJson;
    private int publishAttempts;
    private String lastError;
    private Instant nextAttemptAt;
    private Instant publishedAt;
    private String processingOwner;

    @CreatedDate
    private Instant createdAt;

    @LastModifiedDate
    private Instant updatedAt;

    @Builder
    public ImageJobOutboxDocument(
            String imageJobId,
            String postId,
            ImageJobOutboxStatus status,
            String payloadJson,
            int publishAttempts,
            String lastError,
            Instant nextAttemptAt,
            Instant publishedAt,
            String processingOwner
    ) {
        this.imageJobId = imageJobId;
        this.postId = postId;
        this.status = status;
        this.payloadJson = payloadJson;
        this.publishAttempts = publishAttempts;
        this.lastError = lastError;
        this.nextAttemptAt = nextAttemptAt;
        this.publishedAt = publishedAt;
        this.processingOwner = processingOwner;
    }

    public void markPublished(Instant now) {
        this.status = ImageJobOutboxStatus.PUBLISHED;
        this.publishedAt = now;
        this.lastError = null;
        this.processingOwner = null;
    }

    public void markRetryScheduled(Instant nextAttemptAt, String lastError) {
        this.status = ImageJobOutboxStatus.PENDING;
        this.publishAttempts += 1;
        this.lastError = lastError;
        this.nextAttemptAt = nextAttemptAt;
        this.processingOwner = null;
    }

    public void markProcessing(String processingOwner, Instant leaseUntil) {
        this.status = ImageJobOutboxStatus.PROCESSING;
        this.processingOwner = processingOwner;
        this.nextAttemptAt = leaseUntil;
    }
}
