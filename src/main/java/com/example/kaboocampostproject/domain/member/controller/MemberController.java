package com.example.kaboocampostproject.domain.member.controller;

import com.example.kaboocampostproject.domain.auth.jwt.anotations.MemberIdInfo;
import com.example.kaboocampostproject.domain.auth.service.AuthMemberService;
import com.example.kaboocampostproject.domain.member.dto.request.MemberRegisterReqDTO;
import com.example.kaboocampostproject.domain.member.dto.request.RecoverMemberReqDTO;
import com.example.kaboocampostproject.domain.member.dto.request.UpdateMemberReqDTO;
import com.example.kaboocampostproject.domain.member.dto.response.MemberProfileAndEmailResDTO;
import com.example.kaboocampostproject.domain.member.service.MemberService;
import com.example.kaboocampostproject.global.response.CustomResponse;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/members")
@RequiredArgsConstructor
public class MemberController {

    private final MemberService memberService;
    private final AuthMemberService authMemberService;

    @PostMapping
    public ResponseEntity<CustomResponse<Void>> register(@RequestBody @Valid MemberRegisterReqDTO memberDto) {
        memberService.createMember(memberDto);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.CREATED));
    }

    @GetMapping
    public ResponseEntity<CustomResponse<MemberProfileAndEmailResDTO>> getMemberProfileAndEmail(@MemberIdInfo Long memberId) {

        MemberProfileAndEmailResDTO profile = memberService.getMemberProfileAndEmail(memberId);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.OK, profile));
    }

    // 업데이트

    @PatchMapping("/passwords")
    public ResponseEntity<CustomResponse<Void>> updatePassword(@MemberIdInfo Long memberId,
                                                               @RequestBody @Valid UpdateMemberReqDTO.MemberPassword memberPassword) {

        authMemberService.updatePassword(memberId, memberPassword);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.NO_CONTENT));
    }

    @PatchMapping("names")
    public ResponseEntity<CustomResponse<Void>> updateName(@MemberIdInfo Long memberId,
                                                           @RequestBody @Valid UpdateMemberReqDTO.MemberName memberName) {

        memberService.updateMemberName(memberId, memberName);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.NO_CONTENT));
    }

    @PatchMapping("profileImages")
    public ResponseEntity<CustomResponse<Void>> updateProfileImage(@MemberIdInfo Long memberId,
                                                                   @RequestBody UpdateMemberReqDTO.MemberProfileImage memberProfileImage) {

        memberService.updateMemberImage(memberId, memberProfileImage);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.NO_CONTENT));
    }

    @DeleteMapping
    public ResponseEntity<CustomResponse<Void>> deleteMember(@MemberIdInfo Long memberId,
                                                             HttpServletResponse response) {
        memberService.deleteMember(memberId);
        authMemberService.logout(response);
        return ResponseEntity.ok(CustomResponse.onSuccess(HttpStatus.NO_CONTENT));
    }
}
