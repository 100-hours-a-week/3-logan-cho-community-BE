package com.example.kaboocampostproject.domain.s3.service;


import com.example.kaboocampostproject.domain.s3.dto.req.UploadReqDTO;
import com.example.kaboocampostproject.domain.s3.dto.req.UploadListReqDTO;
import com.example.kaboocampostproject.domain.s3.dto.res.PresignedUrlResDTO;
import com.example.kaboocampostproject.domain.s3.dto.res.PresignedUrlListResDTO;
import com.example.kaboocampostproject.domain.s3.enums.FileDomain;
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
    @Value("${aws.cloudfront.signed-cookie-domain}")
    private String signedCookieDomain;

    public PresignedUrlListResDTO generatePresignedUrls(FileDomain domain, UploadListReqDTO requestList) {
        List<PresignedUrlResDTO> urls = requestList.files().stream()
                .limit(3) // 제한 정책 유지
                .map(file -> generatePresignedUrl(domain, file))
                .toList();

        return new PresignedUrlListResDTO(urls);
    }

    public PresignedUrlResDTO generatePresignedUrl(FileDomain domain, UploadReqDTO file) {
        if (!domain.isMimeTypeAllowed(file.mimeType())) {
            throw new S3Exception(S3ErrorCode.INVALID_FILE_TYPE);
        }

        String uuid = UUID.randomUUID().toString();
        String objectKey = String.format("%s/%s", domain.getBasePath(), uuid);
        String presignedUrl = s3Util.createPresignedUrl(objectKey, file.mimeType());

        return new PresignedUrlResDTO(presignedUrl, objectKey);
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
                    .domain(signedCookieDomain)//cloudFront 도메인
                    .path("/public/") // 퍼블릭 하위
                    .httpOnly(true)
                    .secure(true)
                    .sameSite("None")
                    .maxAge(Duration.ofMinutes(100))
                    .build();
            response.addHeader(HttpHeaders.SET_COOKIE, cookie.toString());
        });

    }

}
