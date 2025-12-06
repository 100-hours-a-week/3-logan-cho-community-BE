package com.example.kaboocampostproject.global.health;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class TestController {

    @Autowired
    private StringRedisTemplate redis;

    @GetMapping("/api/test-redis")
    public String test() {
        System.out.println("connect 성공");
        redis.opsForValue().set("hello", "world");
        System.out.println("set 성공");
        redis.opsForValue().get("hello");
        System.out.println("get 성공");
        return redis.opsForValue().get("hello");
    }
}