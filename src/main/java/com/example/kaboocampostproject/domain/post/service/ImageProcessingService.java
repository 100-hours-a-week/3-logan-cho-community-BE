package com.example.kaboocampostproject.domain.post.service;

import com.example.kaboocampostproject.domain.post.error.PostErrorCode;
import com.example.kaboocampostproject.domain.post.error.PostException;
import com.example.kaboocampostproject.domain.s3.enums.FileDomain;
import com.example.kaboocampostproject.domain.s3.util.S3Util;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import net.coobird.thumbnailator.Thumbnails;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Slf4j
@Service
@RequiredArgsConstructor
public class ImageProcessingService {

    private static final double CONTENT_IMAGE_QUALITY = 0.82d;
    private static final double THUMBNAIL_IMAGE_QUALITY = 0.60d;
    private static final int CONTENT_IMAGE_MAX_SIZE = 1600;
    private static final int THUMBNAIL_IMAGE_MAX_SIZE = 320;

    private final S3Util s3Util;

    public ProcessedImages process(List<String> tempImageKeys) {
        if (tempImageKeys == null || tempImageKeys.isEmpty()) {
            return new ProcessedImages(List.of(), List.of(), List.of());
        }

        long startedAt = System.currentTimeMillis();
        List<String> finalImageKeys = new ArrayList<>();
        List<String> thumbnailKeys = new ArrayList<>();

        for (String tempImageKey : tempImageKeys) {
            byte[] originalBytes = s3Util.getObjectBytes(tempImageKey);
            byte[] finalImageBytes = compressImage(originalBytes, CONTENT_IMAGE_MAX_SIZE, CONTENT_IMAGE_QUALITY);
            byte[] thumbnailBytes = compressImage(originalBytes, THUMBNAIL_IMAGE_MAX_SIZE, THUMBNAIL_IMAGE_QUALITY);

            String finalImageKey = createObjectKey(FileDomain.POST_FINAL);
            String thumbnailKey = createObjectKey(FileDomain.POST_THUMBNAIL);

            s3Util.putObject(finalImageKey, finalImageBytes, MediaType.IMAGE_JPEG_VALUE);
            s3Util.putObject(thumbnailKey, thumbnailBytes, MediaType.IMAGE_JPEG_VALUE);

            finalImageKeys.add(finalImageKey);
            thumbnailKeys.add(thumbnailKey);
        }

        log.info("post images processed. count={}, durationMs={}", tempImageKeys.size(), System.currentTimeMillis() - startedAt);

        return new ProcessedImages(List.copyOf(tempImageKeys), List.copyOf(finalImageKeys), List.copyOf(thumbnailKeys));
    }

    private byte[] compressImage(byte[] originalBytes, int maxSize, double quality) {
        try (ByteArrayInputStream inputStream = new ByteArrayInputStream(originalBytes);
             ByteArrayOutputStream outputStream = new ByteArrayOutputStream()) {

            Thumbnails.of(inputStream)
                    .size(maxSize, maxSize)
                    .outputFormat("jpg")
                    .outputQuality(quality)
                    .useExifOrientation(true)
                    .toOutputStream(outputStream);

            return outputStream.toByteArray();
        } catch (IOException e) {
            throw new PostException(PostErrorCode.POST_IMAGE_PROCESSING_FAILED);
        }
    }

    private String createObjectKey(FileDomain fileDomain) {
        return "%s/%s.jpg".formatted(fileDomain.getBasePath(), UUID.randomUUID());
    }

    public record ProcessedImages(
            List<String> tempImageKeys,
            List<String> finalImageKeys,
            List<String> thumbnailKeys
    ) {
    }
}
