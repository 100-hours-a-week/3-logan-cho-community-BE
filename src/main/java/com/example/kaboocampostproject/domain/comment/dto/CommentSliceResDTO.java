package com.example.kaboocampostproject.domain.comment.dto;

import com.example.kaboocampostproject.global.cursor.PageSlice;
import lombok.Builder;

@Builder
public record CommentSliceResDTO (
        String cdnBaseUrl,
        String parentId, //게시물 id or 부모댓글
        PageSlice<CommentSliceItem> comments
) {
}
