package com.example.jpatest.controller;


import com.example.jpatest.dto.PostDataReqDTO;
import com.example.jpatest.dto.SimplePostResDTO;
import com.example.jpatest.entity.Post;
import com.example.jpatest.service.PostService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RequiredArgsConstructor
@RestController
@RequestMapping("api/post")
public class PostController {

    private final PostService postService;

    @GetMapping
    public ResponseEntity<List<SimplePostResDTO>> getPosts() {
        return ResponseEntity.ok(postService.getSimplePosts());
    }


    @PostMapping
    public ResponseEntity<Boolean> savePost(@RequestBody PostDataReqDTO post) {
        postService.savePost(post);
        return ResponseEntity.ok(true);
    }

    @PutMapping("/{postId}")
    public ResponseEntity<Boolean> updatePost(@PathVariable Long postId, @RequestBody PostDataReqDTO post) {
        postService.updatePost(postId, post);
        return ResponseEntity.ok(true);
    }


    @DeleteMapping
    public ResponseEntity<Boolean> deletePost(@RequestBody Post post) {
        postService.deletePost(post.getId());
        return ResponseEntity.ok(true);
    }
}
