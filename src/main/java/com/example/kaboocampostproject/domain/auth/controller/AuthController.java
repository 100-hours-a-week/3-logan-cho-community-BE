package com.example.kaboocampostproject.domain.auth.controller;

import com.example.kaboocampostproject.domain.auth.dto.req.VerifyEmailReqDTO;
import com.example.kaboocampostproject.domain.auth.dto.res.AccessJwtResDTO;
import com.example.kaboocampostproject.domain.auth.dto.req.SendEmailReqDTO;
import com.example.kaboocampostproject.domain.auth.dto.req.LoginReqDTO;
import com.example.kaboocampostproject.domain.auth.dto.res.SendEmailResDTO;
import com.example.kaboocampostproject.domain.auth.dto.res.VerifyEmailResDTO;
import com.example.kaboocampostproject.domain.auth.email.EmailVerifier;
import com.example.kaboocampostproject.domain.auth.jwt.dto.IssuedJwts;
import com.example.kaboocampostproject.domain.auth.jwt.dto.ReissueJwts;
import com.example.kaboocampostproject.domain.auth.service.AuthMemberService;
import com.example.kaboocampostproject.global.metadata.RedisMetadata;
import com.example.kaboocampostproject.global.response.CustomResponse;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RequiredArgsConstructor
@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final AuthMemberService authMemberService;
    private final EmailVerifier emailVerifier;

    @PostMapping
    public ResponseEntity<CustomResponse<AccessJwtResDTO>> login(@RequestBody LoginReqDTO loginReqDTO,
                                                            HttpServletResponse response) {
        IssuedJwts issued = authMemberService.login(loginReqDTO);
        // 쿠키 세팅
        response.addHeader("Set-Cookie", authMemberService.buildRefreshCookie(issued.refreshJwt()).toString());
        // access jwt 먄 따로 빼서, 응답바디에 반환
        AccessJwtResDTO accessJwtResDTO = AccessJwtResDTO.buildAccessJwtResDTO(issued);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.OK, accessJwtResDTO));
    }

    @PutMapping
    public ResponseEntity<CustomResponse<ReissueJwts>> reissue(HttpServletRequest request) {
        ReissueJwts issued = authMemberService.reissueJwts(request);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.OK, issued));
    }

    @DeleteMapping
    public ResponseEntity<CustomResponse<Void>> logout(HttpServletResponse response){
        authMemberService.logout(response);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.NO_CONTENT));
    }

//    @PostMapping("/check-email")
//    public ResponseEntity<CustomResponse<Boolean>> checkEmailDuplicate(@RequestBody SendEmailReqDTO emailDto) {
//        boolean isDuplicate = authMemberService.isEmailDuplicate(emailDto);
//        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.OK, isDuplicate));
//    }


    /// ===== 회원가입용 ======
    // 이메일 인증코드 발송
    // 재 가입회원 재 요청 필요.
    @PostMapping("/signup/email-verification-code")
    public ResponseEntity<CustomResponse<SendEmailResDTO>> sendEmailVerificationCodeToSignup(
            @RequestBody SendEmailReqDTO sendEmailReqDTO
    ) {
        SendEmailResDTO result = authMemberService.checkDuplicationAndSendEmail(sendEmailReqDTO);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.OK, result));
    }

    // 인증코드 검증, 토큰 발급
    @PutMapping("/signup/email-verification-code")
    public ResponseEntity<CustomResponse<VerifyEmailResDTO>> verifyEmailToSignup(
            @RequestBody VerifyEmailReqDTO verifyEmailReqDTO
    ) {
        String token = emailVerifier.verifyCodeAndIssueToken(
                verifyEmailReqDTO.email(),
                verifyEmailReqDTO.code(),
                RedisMetadata.EMAIL_VERIFICATION_CODE_SIGNUP,
                RedisMetadata.EMAIL_VERIFIED_TOKEN_SIGNUP
        );
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.OK, new VerifyEmailResDTO(token)));
    }

    /// ======== 회원 복구용 ========
    // 이메일 인증코드 발송
    @PostMapping("/recover/email-verification-code")
    public ResponseEntity<CustomResponse<SendEmailResDTO>> sendEmailVerificationCodeToRecover(
            @RequestBody SendEmailReqDTO sendEmailReqDTO
    ) {
        SendEmailResDTO result = authMemberService.checkDuplicationAndSendEmail(sendEmailReqDTO);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.OK, result));
    }

    // 인증코드 검증, 토큰 발급
    @PutMapping("/recover/email-verification-code")
    public ResponseEntity<CustomResponse<VerifyEmailResDTO>> verifyEmailToRecover(
            @RequestBody VerifyEmailReqDTO verifyEmailReqDTO
    ) {
        String token = emailVerifier.verifyCodeAndIssueToken(
                verifyEmailReqDTO.email(),
                verifyEmailReqDTO.code(),
                RedisMetadata.EMAIL_VERIFICATION_CODE_RECOVER,
                RedisMetadata.EMAIL_VERIFIED_TOKEN_RECOVER
        );
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.OK, new VerifyEmailResDTO(token)));
    }


}
