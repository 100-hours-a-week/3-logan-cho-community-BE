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
    // 이렇게 Presigned url 발급 api를 나누는 것이 좋을지
    // /api/images/presigned-url?resource=member&initial=true
    // 와 같은 방식이 좋을지 궁금합니다
    @PostMapping("/members/images/presigned-url")
    public ResponseEntity<CustomResponse<PresignedUrlResDTO>> getProfilePresignedUrl(
            @RequestBody @Valid UploadReqDTO request,
            @MemberIdInfo Long memberId) {

        PresignedUrlResDTO resDTO = s3Service.generateProfilePresignedUrl(memberId, request);

        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.OK, resDTO));
    }
    // 게시물 등록 이전 이미치 첨부 시, {postId}를 모르므로 바디에 nullable 하게 넣기..?
    // 사실 굳이 오브젝트 키에 postId가 필요없긴한데.. 추후 s3에서 파일 관리를 위해서(안할 것 같지만) 넣어두는 것이 나을지...
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
