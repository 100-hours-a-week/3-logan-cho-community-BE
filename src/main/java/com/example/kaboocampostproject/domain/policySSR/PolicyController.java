package com.example.kaboocampostproject.domain.policySSR;


import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;

@Controller
@RequestMapping("/policy")
public class PolicyController {

    @GetMapping("/terms")
    public String terms() {
        return "policy/terms"; // templates/policy/terms.html
    }

    @GetMapping("/privacy")
    public String privacy() {
        return "policy/privacy"; // templates/policy/privacy.html
    }
}
