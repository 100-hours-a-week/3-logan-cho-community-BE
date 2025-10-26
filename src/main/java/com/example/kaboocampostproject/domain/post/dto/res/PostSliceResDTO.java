package com.example.kaboocampostproject.domain.post.dto.res;

import com.example.kaboocampostproject.global.cursor.PageSlice;
import lombok.Builder;

@Builder
public record PostSliceResDTO (
        String cdnBaseUrl,
        PageSlice<PostSliceItem> posts
) {
}
