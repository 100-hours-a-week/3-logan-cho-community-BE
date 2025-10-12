package com.example.kaboocampostproject.domain.comment.controller;

import com.example.kaboocampostproject.domain.auth.jwt.anotations.MemberIdInfo;
import com.example.kaboocampostproject.domain.comment.dto.CommentReqDTO;
import com.example.kaboocampostproject.domain.comment.service.CommentService;
import com.example.kaboocampostproject.global.response.CustomResponse;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequiredArgsConstructor
@RequestMapping("/api/posts/{postId}/comments")
public class CommentController {

    private final CommentService commentService;

    // 댓글 생성
    @PostMapping
    public ResponseEntity<CustomResponse<Void>> createComment(
            @PathVariable String postId,
            @MemberIdInfo Long memberId,
            @RequestBody @Valid CommentReqDTO commentReqDTO
    ) {
        commentService.createComment(memberId, postId, commentReqDTO);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.CREATED));
    }

    // 댓글 수정
    @PutMapping("/{commentId}")
    public ResponseEntity<CustomResponse<Void>> updateComment(
            @PathVariable String postId,
            @PathVariable String commentId,
            @MemberIdInfo Long memberId,
            @RequestBody @Valid CommentReqDTO commentReqDTO
    ) {
        commentService.updateComment(memberId, commentId, commentReqDTO);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.NO_CONTENT));
    }

    // 댓글 삭제
    @DeleteMapping("/{commentId}")
    public ResponseEntity<CustomResponse<Void>> deleteComment(
            @PathVariable String postId,
            @PathVariable String commentId,
            @MemberIdInfo Long memberId
    ) {
        commentService.deleteComment(memberId, commentId);

        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.NO_CONTENT));
    }
}
