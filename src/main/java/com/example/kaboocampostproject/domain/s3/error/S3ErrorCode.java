package com.example.kaboocampostproject.domain.s3.error;

import com.example.kaboocampostproject.global.error.BaseErrorCode;
import lombok.AllArgsConstructor;
import lombok.Getter;
import org.springframework.http.HttpStatus;
@Getter
@AllArgsConstructor
public enum S3ErrorCode implements BaseErrorCode {

    PRESIGNED_URL_FAILED(HttpStatus.INTERNAL_SERVER_ERROR, "S3_500_01", "Presigned URL 생성 실패"),
    DELETE_FAILED(HttpStatus.INTERNAL_SERVER_ERROR, "S3_500_02", "S3 객체 삭제 실패"),
    FILE_NOT_FOUND(HttpStatus.BAD_REQUEST, "S3_400_01", "S3에 파일이 존재하지 않습니다."),
    INVALID_FILE_TYPE(HttpStatus.BAD_REQUEST, "S3_400_02", "이미지 파일이 아닙니다."),
    FILE_TOO_LARGE(HttpStatus.BAD_REQUEST, "S3_400_03", "파일 크기가 너무 큽니다 (10MB 초과)."),
    INVALID_BUCKET_URL(HttpStatus.BAD_REQUEST, "S3_400_04", "잘못된 S3 URL입니다."),
    VERIFICATION_FAILED(HttpStatus.INTERNAL_SERVER_ERROR, "S3_500_03", "S3 업로드 검증 실패"),
    // cloudFront
    CLOUDFRONT_COOKIE_FAIL(HttpStatus.INTERNAL_SERVER_ERROR, "S3_500_03", "CloudFront 쿠키 생성을 실패했습니다."),
    ;

    private final HttpStatus httpStatus;
    private final String code;
    private final String message;
}
