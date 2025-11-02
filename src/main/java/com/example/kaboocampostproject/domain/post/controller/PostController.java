package com.example.kaboocampostproject.domain.post.controller;

import com.example.kaboocampostproject.domain.auth.anotations.MemberIdInfo;
import com.example.kaboocampostproject.domain.post.dto.req.PostCreatReqDTO;
import com.example.kaboocampostproject.domain.post.dto.req.PostUpdateReqDTO;
import com.example.kaboocampostproject.domain.post.dto.res.PostDetailResDTO;
import com.example.kaboocampostproject.domain.post.dto.res.PostSliceResDTO;
import com.example.kaboocampostproject.domain.post.service.PostMongoService;
import com.example.kaboocampostproject.global.cursor.Cursor;
import com.example.kaboocampostproject.global.response.CustomResponse;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequiredArgsConstructor
@RequestMapping("/api/posts")
public class PostController {

    private final PostMongoService postMongoService;

    @PostMapping
    public ResponseEntity<CustomResponse<Void>> createPost(@MemberIdInfo Long memberId,
                                                           @RequestBody PostCreatReqDTO postCreatReqDTO) {
        postMongoService.create(memberId, postCreatReqDTO);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.CREATED));
    }

    @GetMapping("/{postId}")
    public ResponseEntity<CustomResponse<PostDetailResDTO>> getPostDetail(@PathVariable String postId,
                                                                          @MemberIdInfo Long memberId) {
        PostDetailResDTO post = postMongoService.getById(postId, memberId);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.OK, post));
    }

    @GetMapping
    public ResponseEntity<CustomResponse<PostSliceResDTO>> getPostList(
            @RequestParam(required=false) String cursor,
            @RequestParam(required=false, defaultValue="RECENT") Cursor.CursorStrategy strategy,
            @MemberIdInfo Long memberId
    ) {
        PostSliceResDTO result = (cursor != null)
                ? postMongoService.findNext(memberId, cursor)
                : postMongoService.findFirst(memberId, strategy);

        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.OK, result));
    }

    // 게시물 수정
    @PutMapping("/{postId}")
    public ResponseEntity<CustomResponse<Void>> updatePost(
            @PathVariable String postId,
            @RequestBody @Valid PostUpdateReqDTO request,
            @MemberIdInfo Long memberId
    ) {
        postMongoService.updatePost(memberId, postId, request);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.NO_CONTENT));
    }

    // 게시물 삭제
    @DeleteMapping("/{postId}")
    public ResponseEntity<CustomResponse<Void>> deletePost(@PathVariable String postId,
                                                           @MemberIdInfo Long memberId) {
        postMongoService.deletePost(memberId, postId);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.NO_CONTENT));
    }

    @PostMapping("/{postId}/likes")
    public ResponseEntity<CustomResponse<Void>> likePost(@PathVariable String postId,
                                                         @MemberIdInfo Long memberId) {
        postMongoService.likePost(memberId, postId);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.CREATED));
    }

    @DeleteMapping("/{postId}/likes")
    public ResponseEntity<CustomResponse<Void>> unLikePost(@PathVariable String postId,
                                                         @MemberIdInfo Long memberId) {
        postMongoService.unLikePost(memberId, postId);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.NO_CONTENT));
    }
}
