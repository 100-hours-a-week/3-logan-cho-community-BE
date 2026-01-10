package com.example.kaboocampostproject.domain.post.document;


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
    private long likeCount = 0L;
    private long commentCount = 0L;
    private List<String> imageObjectKeys;

    @CreatedDate
    private Instant createdAt;

    @LastModifiedDate
    private Instant updatedAt;

    private Instant deletedAt;

    @Builder
    public PostDocument(Long authorId, String title, String content, List<String> imageObjectKeys) {
        this.authorId = authorId;
        this.title = title;
        this.content = content;
        this.imageObjectKeys = imageObjectKeys;
    }

    // 수정용
    public void setTitle(String title) { this.title = title; }
    public void setContent(String content) { this.content = content; }
    public void setImageObjectKeys(List<String> imageObjectKeys) { this.imageObjectKeys = imageObjectKeys; }
    public void setDeletedAt(Instant deletedAt) { this.deletedAt = deletedAt; }

    public boolean isUpdated() {
        return updatedAt.isAfter(createdAt);
    }
}