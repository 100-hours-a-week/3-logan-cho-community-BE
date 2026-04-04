package com.example.kaboocampostproject.domain.post.service;

import com.example.kaboocampostproject.domain.post.config.ImagePipelineProperties;
import com.example.kaboocampostproject.domain.post.dto.message.AsyncImageJobMessage;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;

@Service
@RequiredArgsConstructor
public class ImageJobPublisher {

    private final SqsClient sqsClient;
    private final ObjectMapper objectMapper;
    private final ImagePipelineProperties imagePipelineProperties;

    public void publish(AsyncImageJobMessage message) {
        String queueUrl = imagePipelineProperties.getQueueUrl();
        if (queueUrl == null || queueUrl.isBlank()) {
            throw new IllegalStateException("image pipeline queue url is missing");
        }

        sqsClient.sendMessage(
                SendMessageRequest.builder()
                        .queueUrl(queueUrl)
                        .messageBody(writeBody(message))
                        .build()
        );
    }

    private String writeBody(AsyncImageJobMessage message) {
        try {
            return objectMapper.writeValueAsString(message);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("failed to serialize async image job message", e);
        }
    }
}
