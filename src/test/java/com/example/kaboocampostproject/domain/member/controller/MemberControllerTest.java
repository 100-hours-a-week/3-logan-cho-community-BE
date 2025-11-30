package com.example.kaboocampostproject.domain.member.controller;

import com.example.kaboocampostproject.domain.member.dto.request.MemberRegisterReqDTO;
import com.example.kaboocampostproject.domain.member.service.MemberService;
import org.junit.jupiter.api.Test;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

import static org.junit.jupiter.api.Assertions.*;
import static reactor.core.publisher.Mono.when;

class MemberControllerTest {

    @MockitoBean
    private MemberService memberService;

    @Test
    void register() {
        MemberRegisterReqDTO memberDto = new MemberRegisterReqDTO("222@naver.com","1111", "조성훈", null, "qwqwqwqw");
        System.out.println(memberDto.name()+ " created successful!");
    }
}