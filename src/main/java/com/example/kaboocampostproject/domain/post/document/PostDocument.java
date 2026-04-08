package com.example.kaboocampostproject.domain.post.document;


import com.example.kaboocampostproject.domain.post.enums.PostImageStatus;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Builder;
import lombok.experimental.FieldNameConstants;
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.annotation.LastModifiedDate;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.CompoundIndexes;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

@Document(collection = "posts")
@CompoundIndexes({
        // 최신순: where deletedAt == null, sort by createdAt desc, _id desc
        @CompoundIndex(
                name = "idx_post_recent_active",
                def  = "{ 'deletedAt': 1, 'createdAt': -1, '_id': -1 }"
        ),
        // 인기순: where deletedAt == null, sort by view desc, createdAt desc, _id desc
        @CompoundIndex(
                name = "idx_post_popular_active",
                def  = "{ 'deletedAt': 1, 'views': -1, 'createdAt': -1, '_id': -1 }"
        )
})
@Getter
@NoArgsConstructor
@FieldNameConstants(innerTypeName = "PostFields")
public class PostDocument {

    @Id
    private String id;

    @Indexed(name = "idx_authorId")
    private Long authorId;

    private String title;
    private String content;
    private long views = 0L;
    private List<String> imageObjectKeys;
    private PostImageStatus imageStatus;
    private String imageJobId;
    private String failureReason;
    private List<String> tempImageKeys;
    private List<String> finalImageKeys;
    private List<String> thumbnailKeys;
    private Instant completedAt;

    private long likes = 0L;
    private long comments = 0L;

    @CreatedDate
    private Instant createdAt;

    @LastModifiedDate
    private Instant updatedAt;

    private Instant deletedAt;

    @Builder
    public PostDocument(Long authorId, String title, String content, List<String> imageObjectKeys,
                        PostImageStatus imageStatus, String imageJobId, String failureReason,
                        List<String> tempImageKeys, List<String> finalImageKeys,
                        List<String> thumbnailKeys, Instant completedAt) {
        this.authorId = authorId;
        this.title = title;
        this.content = content;
        this.imageObjectKeys = imageObjectKeys != null ? new ArrayList<>(imageObjectKeys) : new ArrayList<>();
        this.imageStatus = imageStatus;
        this.imageJobId = imageJobId;
        this.failureReason = failureReason;
        this.tempImageKeys = tempImageKeys != null ? new ArrayList<>(tempImageKeys) : new ArrayList<>();
        this.finalImageKeys = finalImageKeys != null ? new ArrayList<>(finalImageKeys) : new ArrayList<>();
        this.thumbnailKeys = thumbnailKeys != null ? new ArrayList<>(thumbnailKeys) : new ArrayList<>();
        this.completedAt = completedAt;
    }

    // 수정용
    public void setTitle(String title) { this.title = title; }
    public void setContent(String content) { this.content = content; }
    public void setImageObjectKeys(List<String> imageObjectKeys) { this.imageObjectKeys = imageObjectKeys; }
    public void setImageStatus(PostImageStatus imageStatus) { this.imageStatus = imageStatus; }
    public void setImageJobId(String imageJobId) { this.imageJobId = imageJobId; }
    public void setFailureReason(String failureReason) { this.failureReason = failureReason; }
    public void setTempImageKeys(List<String> tempImageKeys) { this.tempImageKeys = tempImageKeys; }
    public void setFinalImageKeys(List<String> finalImageKeys) { this.finalImageKeys = finalImageKeys; }
    public void setThumbnailKeys(List<String> thumbnailKeys) { this.thumbnailKeys = thumbnailKeys; }
    public void setCompletedAt(Instant completedAt) { this.completedAt = completedAt; }
    public void setDeletedAt(Instant deletedAt) { this.deletedAt = deletedAt; }

    public boolean isUpdated() {
        return updatedAt.isAfter(createdAt);
    }
}
