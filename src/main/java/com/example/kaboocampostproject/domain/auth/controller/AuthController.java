package com.example.kaboocampostproject.domain.auth.controller;

import com.example.kaboocampostproject.domain.auth.dto.req.LoginReqDTO;
import com.example.kaboocampostproject.domain.auth.service.AuthMemberService;
import com.example.kaboocampostproject.global.response.CustomResponse;
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
    public ResponseEntity<CustomResponse<Void>> login(@RequestBody LoginReqDTO loginReqDTO,
                                                            HttpServletResponse response) {
        authMemberService.login(response, loginReqDTO);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.CREATED));
    }

    @DeleteMapping
    public ResponseEntity<CustomResponse<Void>> logout(HttpServletResponse response){
        authMemberService.logout(response);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.NO_CONTENT));
    }


}
