package com.example.kaboocampostproject.global.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.util.List;

@ConfigurationProperties(prefix = "app.security")
public class SecurityProperties {

    private List<String> publicApis;
    private List<String> jwtExcludePaths;

    public List<String> getPublicApis() {
        return publicApis;
    }

    public void setPublicApis(List<String> publicApis) {
        this.publicApis = publicApis;
    }

}
