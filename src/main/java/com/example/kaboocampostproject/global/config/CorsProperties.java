package com.example.kaboocampostproject.global.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.util.List;

@ConfigurationProperties(prefix = "app.cors")
public class CorsProperties {

    private List<String> allowedOriginPatterns;
    private List<String> credPaths;

    public List<String> getAllowedOriginPatterns() {
        return allowedOriginPatterns;
    }

    public void setAllowedOriginPatterns(List<String> allowedOriginPatterns) {
        this.allowedOriginPatterns = allowedOriginPatterns;
    }

    public List<String> getCredPaths() {
        return credPaths;
    }

    public void setCredPaths(List<String> credPaths) {
        this.credPaths = credPaths;
    }
}
