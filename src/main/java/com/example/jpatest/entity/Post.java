package com.example.jpatest.entity;

import com.example.jpatest.dto.PostDataReqDTO;
import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
@Entity
public class Post extends BaseEntity{
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(length = 100)
    private String title;
    @Column(length = 500)
    private String content;
    @Column(length = 255)
    private String imageUrl;

    @ManyToOne
    @JoinColumn(name = "user_id")
    private User author;


    public void updatePost(PostDataReqDTO postDto) {
        this.title = postDto.title();
        this.content = postDto.content();
        this.imageUrl = postDto.imageUrl();
    }
}
