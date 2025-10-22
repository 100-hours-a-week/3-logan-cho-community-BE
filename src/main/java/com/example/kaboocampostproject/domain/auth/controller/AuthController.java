package com.example.kaboocampostproject.domain.auth.controller;

import com.example.kaboocampostproject.domain.auth.dto.AccessJwtResDTO;
import com.example.kaboocampostproject.domain.auth.dto.EmailCheckReqDTO;
import com.example.kaboocampostproject.domain.auth.dto.LoginReqDTO;
import com.example.kaboocampostproject.domain.auth.jwt.dto.IssuedJwts;
import com.example.kaboocampostproject.domain.auth.jwt.dto.ReissueJwts;
import com.example.kaboocampostproject.domain.auth.service.AuthMemberService;
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

    @PostMapping("/check-email")
    public ResponseEntity<CustomResponse<Boolean>> checkEmailDuplicate(@RequestBody EmailCheckReqDTO emailDto) {
        boolean isDuplicate = authMemberService.isEmailDuplicate(emailDto);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.OK, isDuplicate));
    }
}
