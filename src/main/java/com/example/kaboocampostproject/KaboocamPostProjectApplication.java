package com.example.kaboocampostproject;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.data.jpa.repository.config.EnableJpaAuditing;

@SpringBootApplication
@EnableJpaAuditing
public class KaboocamPostProjectApplication {

    public static void main(String[] args) {
        SpringApplication.run(KaboocamPostProjectApplication.class, args);
    }

}
