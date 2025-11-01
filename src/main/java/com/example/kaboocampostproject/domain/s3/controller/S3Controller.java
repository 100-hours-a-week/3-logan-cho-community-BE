package com.example.kaboocampostproject.domain.s3.controller;


import com.example.kaboocampostproject.domain.s3.dto.req.UploadListReqDTO;
import com.example.kaboocampostproject.domain.s3.dto.req.UploadReqDTO;
import com.example.kaboocampostproject.domain.s3.dto.res.PresignedUrlListResDTO;
import com.example.kaboocampostproject.domain.s3.dto.res.PresignedUrlResDTO;
import com.example.kaboocampostproject.domain.s3.enums.FileDomain;
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
            @RequestBody @Valid UploadReqDTO request) {

        FileDomain fileDomain = FileDomain.PROFILE;

        PresignedUrlResDTO resDTO = s3Service.generatePresignedUrl(fileDomain, request);

        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.OK, resDTO));
    }

    @PostMapping("/posts/images/presigned-url")
    public ResponseEntity<CustomResponse<PresignedUrlListResDTO>> getPostImagePresignedUrl(
            @RequestBody @Valid UploadListReqDTO request) {

        FileDomain fileDomain = FileDomain.POST;

        PresignedUrlListResDTO resDTO = s3Service.generatePresignedUrls(fileDomain, request);

        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.OK, resDTO));
    }

    @PostMapping("/images/signed-cookie")
    public ResponseEntity<CustomResponse<Void>> issueSignedCookieForView(
            HttpServletResponse response) {
        s3Service.generateSignedCookieForView( response);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.NO_CONTENT));
    }

}
