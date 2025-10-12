package com.example.kaboocampostproject.domain.comment.converter;

import com.example.kaboocampostproject.domain.comment.document.CommentDocument;
import com.example.kaboocampostproject.domain.comment.dto.CommentReqDTO;

public class CommentConverter {
    public static CommentDocument toEntity(Long memberId, String postId, CommentReqDTO comment) {
        return CommentDocument.builder()
                .authorId(memberId)
                .postId(postId)
                .content(comment.content())
                .build();
    }
}
