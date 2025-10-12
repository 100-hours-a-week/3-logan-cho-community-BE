package com.example.kaboocampostproject.domain.comment.error;

import com.example.kaboocampostproject.global.error.BaseErrorCode;
import lombok.Getter;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;

@Getter
@RequiredArgsConstructor
public enum CommentErrorCode implements BaseErrorCode {

    COMMENT_NOT_FOUND(HttpStatus.NOT_FOUND, "COMMENT_404_01", "존재하지 않는 댓글입니다."),
    COMMENT_AUTHOR_NOT_MATCH(HttpStatus.FORBIDDEN, "COMMENT_403_01", "댓글 작성자만 삭제할 수 있습니다."),
    ;
    private final HttpStatus httpStatus;
    private final String code;
    private final String message;

}
