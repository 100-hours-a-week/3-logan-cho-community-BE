package com.example.kaboocampostproject.domain.post.config;

import lombok.Getter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Getter
@Component
public class ImagePipelineProperties {

    @Value("${image.pipeline.async-enabled:false}")
    private boolean asyncEnabled;

    @Value("${image.pipeline.queue-url:}")
    private String queueUrl;

    @Value("${image.pipeline.callback-base-url:}")
    private String callbackBaseUrl;

    @Value("${image.pipeline.callback-secret:}")
    private String callbackSecret;
}
