package com.example.kaboocampostproject.domain.s3.enums;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

import java.util.List;

@Getter
@RequiredArgsConstructor
public enum FileDomain {
    PROFILE("public/images/profiles", "image/"),
    POST_TEMP("temp/images/posts", "image/"),
    POST_FINAL("public/images/posts", "image/"),
    POST_THUMBNAIL("public/images/posts/thumbnails", "image/"),

    ;

    private final String basePath;
    private final String allowedMimePrefix;

    public boolean isMimeTypeAllowed(String mimeType) {
        return mimeType.startsWith(allowedMimePrefix);
    }
}
