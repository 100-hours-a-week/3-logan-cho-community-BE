package com.example.jpatest.service;

import com.example.jpatest.dto.PostDataReqDTO;
import com.example.jpatest.dto.SimplePostResDTO;
import com.example.jpatest.entity.Post;
import com.example.jpatest.repository.PostRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor
@Transactional
public class PostService {

    private final PostRepository postRepository;

    @Transactional(readOnly = true)
    public List<SimplePostResDTO> getSimplePosts() {
        return postRepository.findSimplePostsOrderByDesc();
    }

    public void savePost(PostDataReqDTO postDto) {
        postRepository.save(postDto.toEntity());
    }

    public void updatePost(long postId, PostDataReqDTO postDto) {
        Post post = postRepository.findById(postId).orElseThrow(() ->new RuntimeException("게시물 없음"));
        post.updatePost(postDto);
    }

    public void deletePost(long postId) {
        postRepository.deleteById(postId);
    }
}
