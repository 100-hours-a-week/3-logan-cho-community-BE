package com.example.kaboocampostproject.domain.post.repository;

import com.example.kaboocampostproject.domain.post.document.ImageJobOutboxDocument;

import java.time.Instant;
import java.util.Optional;

public interface ImageJobOutboxClaimRepository {

    Optional<ImageJobOutboxDocument> claimNextRelayCandidate(Instant now, Instant leaseUntil, String processingOwner);

    boolean completeRelayAttempt(String outboxId, String processingOwner, boolean published, Instant nextAttemptAt, String lastError);
}
