package com.example.kaboocampostproject.domain.s3.enums;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

import java.util.List;

@Getter
@RequiredArgsConstructor
public enum FileDomain {
    PROFILE("public/images/profiles", "image/"),
    POST("public/images/posts","image/"),

    ;

    private final String basePath;
    private final String allowedMimePrefix;

    public boolean isMimeTypeAllowed(String mimeType) {
        return mimeType.startsWith(allowedMimePrefix);
    }
}
