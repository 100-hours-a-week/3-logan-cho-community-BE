package com.example.kaboocampostproject.domain.post.error;

import com.example.kaboocampostproject.global.error.BaseErrorCode;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;

@Getter
@RequiredArgsConstructor
public enum PostErrorCode implements BaseErrorCode {

    POST_NOT_FOUND(HttpStatus.NOT_FOUND, "POST_404_01", "존재하지 않는 게시물입니다."),
    POST_AUTHOR_NOT_MATCH(HttpStatus.FORBIDDEN, "POST_403_01", "게시물 작성자만 삭제할 수 있습니다."),
    TOO_MANY_IMAGES(HttpStatus.BAD_REQUEST, "POST_401_01","이미지는 3개까지 등록 가능합니다"),
    POST_UPDATED_FAIL(HttpStatus.BAD_REQUEST, "POST_401_02", "작성자 불일치, 혹은 이미 삭제된 게시물입니다."),
    POST_IMAGE_NOT_FOUND(HttpStatus.NOT_FOUND, "POST_404_02", "삭제요청된 이미지가 존재하지 않습니다."),
    POST_IMAGE_PROCESSING_FAILED(HttpStatus.INTERNAL_SERVER_ERROR, "POST_500_01", "게시글 이미지 처리에 실패했습니다."),
    POST_IMAGE_JOB_CALLBACK_UNAUTHORIZED(HttpStatus.UNAUTHORIZED, "POST_401_03", "이미지 작업 콜백 인증에 실패했습니다."),
    POST_IMAGE_JOB_MISMATCH(HttpStatus.BAD_REQUEST, "POST_400_01", "이미지 작업 식별자가 일치하지 않습니다.")
    ;
    private final HttpStatus httpStatus;
    private final String code;
    private final String message;

}
