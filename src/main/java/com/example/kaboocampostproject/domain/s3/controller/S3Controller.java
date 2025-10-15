package com.example.kaboocampostproject.domain.s3.controller;


import com.example.kaboocampostproject.domain.auth.jwt.anotations.MemberIdInfo;
import com.example.kaboocampostproject.domain.s3.dto.req.UploadListReqDTO;
import com.example.kaboocampostproject.domain.s3.dto.req.UploadReqDTO;
import com.example.kaboocampostproject.domain.s3.dto.res.PresignedUrlListResDTO;
import com.example.kaboocampostproject.domain.s3.dto.res.PresignedUrlResDTO;
import com.example.kaboocampostproject.domain.s3.service.S3Service;
import com.example.kaboocampostproject.global.response.CustomResponse;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequiredArgsConstructor
@RequestMapping("/api")
public class S3Controller {

    private final S3Service s3Service;

    @PostMapping("/members/images/presigned-url")
    public ResponseEntity<CustomResponse<PresignedUrlResDTO>> getProfilePresignedUrl(
            @RequestBody @Valid UploadReqDTO request,
            @MemberIdInfo Long memberId) {

        PresignedUrlResDTO resDTO = s3Service.generateProfilePresignedUrl(memberId, request);

        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.OK, resDTO));
    }

    @PostMapping("/posts/{postId}/images/presigned-url")
    public ResponseEntity<CustomResponse<PresignedUrlListResDTO>> getPostImagePresignedUrl(
            @PathVariable Long postId,
            @RequestBody @Valid UploadListReqDTO request) {

        PresignedUrlListResDTO resDTO = s3Service.generatePostPresignedUrls(postId, request);

        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.OK, resDTO));
    }
    // 이미지 조회용 CloudFront Signed Cookie 발급
    @PostMapping("/cloud-front/images/signed-cookie")
    public ResponseEntity<CustomResponse<Void>> issueSignedCookieForView(
            HttpServletResponse response) {
        s3Service.generateSignedCookieForView( response);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.NO_CONTENT));
    }

}
