package com.example.kaboocampostproject.domain.post.document;

import com.example.kaboocampostproject.domain.post.enums.PostImageStatus;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.annotation.Id;
import org.springframework.data.annotation.LastModifiedDate;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

import java.time.Instant;

@Getter
@NoArgsConstructor
@Document(collection = "image_job_processed")
public class ImageJobProcessedDocument {

    @Id
    private String id;

    @Indexed(unique = true)
    private String imageJobId;

    @Indexed
    private String postId;

    private PostImageStatus imageStatus;
    private int sideEffectApplyCount;
    private int callbackReceiveCount;
    private int duplicateIgnoredCount;
    private String failureReason;

    @CreatedDate
    private Instant createdAt;

    @LastModifiedDate
    private Instant updatedAt;

    @Builder
    public ImageJobProcessedDocument(String imageJobId,
                                     String postId,
                                     PostImageStatus imageStatus,
                                     int sideEffectApplyCount,
                                     int callbackReceiveCount,
                                     int duplicateIgnoredCount,
                                     String failureReason) {
        this.imageJobId = imageJobId;
        this.postId = postId;
        this.imageStatus = imageStatus;
        this.sideEffectApplyCount = sideEffectApplyCount;
        this.callbackReceiveCount = callbackReceiveCount;
        this.duplicateIgnoredCount = duplicateIgnoredCount;
        this.failureReason = failureReason;
    }

    public void markDuplicateCallback() {
        this.callbackReceiveCount += 1;
        this.duplicateIgnoredCount += 1;
    }
}
