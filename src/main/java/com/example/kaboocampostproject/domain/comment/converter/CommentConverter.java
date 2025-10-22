package com.example.kaboocampostproject.domain.comment.converter;

import com.example.kaboocampostproject.domain.comment.document.CommentDocument;
import com.example.kaboocampostproject.domain.comment.dto.CommentReqDTO;
import com.example.kaboocampostproject.domain.comment.dto.CommentSliceItem;
import com.example.kaboocampostproject.domain.member.cache.MemberProfileCacheDTO;
import com.example.kaboocampostproject.domain.s3.util.CloudFrontUtil;

public class CommentConverter {
    public static CommentDocument toEntity(Long memberId, String postId, CommentReqDTO comment) {
        return CommentDocument.builder()
                .authorId(memberId)
                .postId(postId)
                .content(comment.content())
                .build();
    }

    public static CommentSliceItem toSliceItem(CommentDocument comment, MemberProfileCacheDTO authorProfile) {

        CommentSliceItem.AuthorProfile author = null;
        if (authorProfile != null) {
            author = CommentSliceItem.AuthorProfile.builder()
                    .id(authorProfile.id())
                    .name(authorProfile.name())
                    .profileImageObjectKey(authorProfile.profileImageObjectKey())
                    .build();
        }

        return CommentSliceItem.builder()
                .commentId(comment.getId())
                .content(comment.getContent())
                .createdAt(comment.getCreatedAt())
                .isUpdated(comment.isUpdated())
                .author(author)
                .build();
    }
}
