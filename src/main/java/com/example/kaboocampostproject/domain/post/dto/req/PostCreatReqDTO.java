package com.example.kaboocampostproject.domain.post.dto.req;

import java.util.List;

public record PostCreatReqDTO (
        String title,
        String content,
        List<String> imageUrls
){
}
