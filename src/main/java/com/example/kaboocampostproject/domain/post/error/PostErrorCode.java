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
    TOO_MANY_IMAGES(HttpStatus.BAD_REQUEST, "POST_401_01","이미지는 3개까지 등록 가능합니다")
    ;
    private final HttpStatus httpStatus;
    private final String code;
    private final String message;

}
