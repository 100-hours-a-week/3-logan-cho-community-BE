package com.example.kaboocampostproject.domain.comment.controller;

import com.example.kaboocampostproject.domain.auth.jwt.anotations.MemberIdInfo;
import com.example.kaboocampostproject.domain.comment.dto.CommentReqDTO;
import com.example.kaboocampostproject.domain.comment.dto.CommentSliceResDTO;
import com.example.kaboocampostproject.domain.comment.service.CommentMongoService;
import com.example.kaboocampostproject.global.response.CustomResponse;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequiredArgsConstructor
@RequestMapping("/api/posts")
public class CommentController {

    private final CommentMongoService commentService;

    // 댓글 생성
    @PostMapping("/{postId}/comments")
    public ResponseEntity<CustomResponse<Void>> createComment(
            @PathVariable String postId,
            @MemberIdInfo Long memberId,
            @RequestBody @Valid CommentReqDTO commentReqDTO
    ) {
        commentService.createComment(memberId, postId, commentReqDTO);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.CREATED));
    }

    // 댓글 수정
    @PutMapping("/comments/{commentId}")
    public ResponseEntity<CustomResponse<Void>> updateComment(
            @PathVariable String commentId,
            @MemberIdInfo Long memberId,
            @RequestBody @Valid CommentReqDTO commentReqDTO
    ) {
        commentService.updateComment(memberId, commentId, commentReqDTO);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.NO_CONTENT));
    }

    // 댓글 삭제
    @DeleteMapping("/comments/{commentId}")
    public ResponseEntity<CustomResponse<Void>> deleteComment(
            @PathVariable String commentId,
            @MemberIdInfo Long memberId
    ) {
        commentService.deleteComment(memberId, commentId);

        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.NO_CONTENT));
    }


    @GetMapping("/{postId}/comments")
    public ResponseEntity<CustomResponse<CommentSliceResDTO>> getCommentList(
            @PathVariable String postId,
            @RequestParam(required=false) String cursor,
            @MemberIdInfo Long memberId
    ) {
        CommentSliceResDTO result = (cursor != null)
                ? commentService.findNextByPost(memberId, postId, cursor)
                : commentService.findFirstByPost(memberId, postId);

        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.OK, result));
    }
}
