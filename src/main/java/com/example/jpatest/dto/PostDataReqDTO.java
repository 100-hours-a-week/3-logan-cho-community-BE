package com.example.jpatest.dto;

import com.example.jpatest.entity.Post;

public record PostDataReqDTO(
        String title,
        String content,
        String imageUrl
){
    public Post toEntity (){
        return Post.builder()
                .title(title)
                .content(content)
                .imageUrl(imageUrl).build();
    }
}
