package com.example.kaboocampostproject.domain.s3.service;


import com.example.kaboocampostproject.domain.s3.dto.req.UploadReqDTO;
import com.example.kaboocampostproject.domain.s3.dto.req.UploadListReqDTO;
import com.example.kaboocampostproject.domain.s3.dto.res.PresignedUrlResDTO;
import com.example.kaboocampostproject.domain.s3.dto.res.PresignedUrlListResDTO;
import com.example.kaboocampostproject.domain.s3.error.S3ErrorCode;
import com.example.kaboocampostproject.domain.s3.error.S3Exception;
import com.example.kaboocampostproject.domain.s3.util.CloudFrontUtil;
import com.example.kaboocampostproject.domain.s3.util.S3Util;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseCookie;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.s3.model.HeadObjectResponse;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;

import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class S3Service  {
    private final S3Util s3Util;
    private final CloudFrontUtil cloudFrontUtil;


    @Value("${aws.s3.bucket}")
    private String bucket;

    // 프로필 이미지 Presigned URL 생성 (오브젝트 키 : 덮어쓰기)
    public PresignedUrlResDTO generateProfilePresignedUrl(Long memberId, UploadReqDTO request) {
        String objectKey = String.format("images/profiles/%d", memberId);
        // 이미지만 받기
        if (!request.mimeType().startsWith("image/")) {
            throw new S3Exception(S3ErrorCode.INVALID_FILE_TYPE);
        }
        String presignedUrl = s3Util.createPresignedUrl(objectKey, request.mimeType());
        return new PresignedUrlResDTO(presignedUrl, objectKey);
    }

    // 게시물 이미지 Presigned URL 생성 (오브젝트 키 : 매번 생성)
    public PresignedUrlListResDTO generatePostPresignedUrls(Long postId, UploadListReqDTO requestList) {
        List<PresignedUrlResDTO> urls = requestList.files().stream()
                .limit(3) // 최대 3장 제한
                .map(file -> {
                    //이미지만 받기
                    if (!file.mimeType().startsWith("image/")) {
                        throw new S3Exception(S3ErrorCode.INVALID_FILE_TYPE);
                    }
                    String uuid = UUID.randomUUID().toString();
                    String objectKey = String.format("images/posts/%d/%s-%s", postId, uuid, file.fileName());
                    String presignedUrl = s3Util.createPresignedUrl(objectKey, file.mimeType());
                    return new PresignedUrlResDTO(presignedUrl, objectKey);
                })
                .toList();

        return new PresignedUrlListResDTO(urls);
    }

    // 업로드 검증
    public void verifyS3Upload(String objectKey) {
        try {
            HeadObjectResponse head = s3Util.headObject(objectKey);
            long fileSize = head.contentLength();
            String contentType = head.contentType();

            if (fileSize > 10 * 1024 * 1024) {// 최대 크기 10MB
                s3Util.delete(objectKey);
                throw new S3Exception(S3ErrorCode.FILE_TOO_LARGE);
            }

            if (!contentType.startsWith("image/")) {// 이미지만
                s3Util.delete(objectKey);
                throw new S3Exception(S3ErrorCode.INVALID_FILE_TYPE);
            }

        } catch (NoSuchKeyException e) {
            throw new S3Exception(S3ErrorCode.FILE_NOT_FOUND);
        } catch (Exception e) {
            s3Util.delete(objectKey);
            throw new S3Exception(S3ErrorCode.VERIFICATION_FAILED);
        }
    }


    // signed cookie 이미지 조회
    public void generateSignedCookieForView(HttpServletResponse response) {

        Map<String, String> cookies = cloudFrontUtil.generateSignedCookies(Duration.ofMinutes(100));

        cookies.forEach((name, value) -> {
            ResponseCookie cookie = ResponseCookie.from(name, value)
                    .domain(".syncly-io.com")//cloudFront 도메인
                    .path("/") // or specific resource
                    .httpOnly(true)
                    .secure(true)
                    .sameSite("None")
                    .maxAge(Duration.ofMinutes(100))
                    .build();
            response.addHeader(HttpHeaders.SET_COOKIE, cookie.toString());
        });

    }

}
