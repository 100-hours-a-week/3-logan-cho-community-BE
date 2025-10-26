package com.example.kaboocampostproject.domain.comment.document;


import lombok.AccessLevel;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.experimental.FieldNameConstants;
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.annotation.Id;
import org.springframework.data.annotation.LastModifiedDate;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

import java.time.Instant;

@Document(collection = "comments")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@FieldNameConstants(innerTypeName = "CommentFields")
@CompoundIndex(
        name = "idx_postId_createdAt_desc",
        def = "{'postId': 1, 'createdAt': -1}"
)
public class CommentDocument {

    @Id
    private String id;

    @Indexed(name = "idx_postId")
    private String postId;

    @Indexed(name = "idx_authorId")
    private Long authorId;

    private String content;

    @CreatedDate
    private Instant createdAt;

    @LastModifiedDate
    private Instant updatedAt;

    private Instant deletedAt;

    @Builder
    public CommentDocument(Long authorId, String postId, String content) {
        this.authorId = authorId;
        this.postId = postId;
        this.content = content;
    }

    public void setContent(String content) {
        this.content = content;
    }
    // 소프트 딜리트
    public void setDeletedAt(Instant deletedAt) {
        this.deletedAt = deletedAt;
    }

    public boolean isUpdated() {
        return updatedAt.isAfter(createdAt);
    }
}
