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

    public static CommentSliceItem toSliceItem(CommentDocument comment, MemberProfileCacheDTO authorProfile, boolean isMine) {

        CommentSliceItem.AuthorProfile author = CommentSliceItem.AuthorProfile.builder()
                .id(authorProfile!=null ? authorProfile.id() : null)
                .name(authorProfile!=null ? authorProfile.name() : "(탈퇴한 사용자)")
                .profileImageObjectKey(authorProfile!=null ? authorProfile.profileImageObjectKey() : null)
                .build();

        return CommentSliceItem.builder()
                .commentId(comment.getId())
                .content(comment.getContent())
                .createdAt(comment.getCreatedAt())
                .isUpdated(comment.isUpdated())
                .author(author)
                .isMine(isMine)
                .build();
    }
}
