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

    @Value("${image.pipeline.outbox-enabled:false}")
    private boolean outboxEnabled;

    @Value("${image.pipeline.outbox.relay-enabled:false}")
    private boolean outboxRelayEnabled;

    @Value("${image.pipeline.outbox.relay-fixed-delay-ms:1000}")
    private long outboxRelayFixedDelayMs;

    @Value("${image.pipeline.outbox.relay-batch-size:20}")
    private int outboxRelayBatchSize;

    @Value("${image.pipeline.idempotency-enabled:false}")
    private boolean idempotencyEnabled;

    @Value("${image.pipeline.fault.fail-after-save-before-publish-enabled:false}")
    private boolean failAfterSaveBeforePublishEnabled;

    @Value("${image.pipeline.fault.fail-after-save-title-prefix:[fault-save-publish]}")
    private String failAfterSaveTitlePrefix;
}
