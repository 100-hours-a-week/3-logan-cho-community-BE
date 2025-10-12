package com.example.kaboocampostproject.domain.comment.service;

import com.example.kaboocampostproject.domain.comment.converter.CommentConverter;
import com.example.kaboocampostproject.domain.comment.document.CommentDocument;
import com.example.kaboocampostproject.domain.comment.dto.CommentReqDTO;
import com.example.kaboocampostproject.domain.comment.dto.CommentSliceItem;
import com.example.kaboocampostproject.domain.comment.error.CommentErrorCode;
import com.example.kaboocampostproject.domain.comment.error.CommentException;
import com.example.kaboocampostproject.domain.comment.repository.CommentMongoRepository;
import com.example.kaboocampostproject.domain.member.cache.MemberProfileCacheDTO;
import com.example.kaboocampostproject.domain.member.cache.MemberProfileCacheService;
import com.example.kaboocampostproject.global.cursor.Cursor;
import com.example.kaboocampostproject.global.cursor.CursorCodec;
import com.example.kaboocampostproject.global.cursor.PageSlice;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.Map;

@Service
@RequiredArgsConstructor
@Transactional
public class CommentService {

    private static final int PAGE_SIZE = 10;

    private final CommentMongoRepository commentRepository;

    private final MemberProfileCacheService memberProfileCacheService;
    private final CursorCodec cursorCodec;

    @Transactional
    public void createComment(Long memberId, String postId, CommentReqDTO dto) {
        commentRepository.save(CommentConverter.toEntity(memberId, postId, dto));
    }

    @Transactional
    public void updateComment(Long memberId, String commentId, CommentReqDTO dto) {
        CommentDocument comment = commentRepository.findByIdAndDeletedAtIsNull(commentId)
                .orElseThrow(() -> new CommentException(CommentErrorCode.COMMENT_NOT_FOUND));

        if (!comment.getAuthorId().equals(memberId))
            throw new CommentException(CommentErrorCode.COMMENT_AUTHOR_NOT_MATCH);

        comment.setContent(dto.content());
        commentRepository.save(comment);
    }

    @Transactional
    public void deleteComment(Long memberId, String commentId) {
        CommentDocument comment = commentRepository.findByIdAndDeletedAtIsNull(commentId)
                .orElseThrow(() -> new CommentException(CommentErrorCode.COMMENT_NOT_FOUND));

        if (!comment.getAuthorId().equals(memberId))
            throw new CommentException(CommentErrorCode.COMMENT_AUTHOR_NOT_MATCH);


        comment.setDeletedAt(Instant.now());
        commentRepository.save(comment);
    }

    // =====================커서로 조회하는 메서드=====================

    // 최신 순 첫페이지
    @Transactional(readOnly = true)
    public PageSlice<CommentSliceItem> findFirstByPost(String postId) {
        List<CommentDocument> docs =
                commentRepository.findFirstByPostIdOrderByCreatedAtDesc(postId, PAGE_SIZE + 1);

        return buildSlice(postId, docs);
    }

    // 최신 순 다음 페이지
    @Transactional(readOnly = true)
    public PageSlice<CommentSliceItem> findNextByPost(String postId, String cursorToken) {
        Cursor cursor = cursorCodec.decode(cursorToken);
        if (cursor.strategy() != Cursor.CursorStrategy.RECENT) {
            throw new IllegalArgumentException("지원하지 않는 커서 전략입니다: " + cursor.strategy());
        }

        Cursor.CreatedAtPos pos = (Cursor.CreatedAtPos) cursor.pos();
        List<CommentDocument> docs =
                commentRepository.findNextByPostIdOrderByCreatedAtDesc(
                        postId, pos.createdAt(), pos.id(), PAGE_SIZE + 1);

        return buildSlice(postId, docs);
    }

    // 멤버프로필 가져와서 PageSlice 생성하기
    private PageSlice<CommentSliceItem> buildSlice(String postId, List<CommentDocument> docsPlusOne) {
        boolean hasNext = docsPlusOne.size() > PAGE_SIZE;
        List<CommentDocument> content = hasNext ? docsPlusOne.subList(0, PAGE_SIZE) : docsPlusOne;

        if (content.isEmpty()) {
            return new PageSlice<>(postId, List.of(), null, false);
        }

        // 작성자 프로필 일괄 조회 (redis -> mysql)
        List<Long> authorIds = content.stream()
                .map(CommentDocument::getAuthorId)
                .distinct()
                .toList();
        Map<Long, MemberProfileCacheDTO> profiles = memberProfileCacheService.getProfiles(authorIds);

        // 매핑
        List<CommentSliceItem> items = content.stream()
                .map(doc -> {
                    MemberProfileCacheDTO p = profiles.get(doc.getAuthorId());
                    CommentSliceItem.AuthorProfile author = CommentSliceItem.AuthorProfile.builder()
                            .id(p != null ? p.id() : null)
                            .name(p != null ? p.name() : null)
                            .profileImageUrl(p != null ? p.profileImageUrl() : null)
                            .build();

                    boolean isUpdated = doc.getUpdatedAt() != null
                            && doc.getCreatedAt() != null
                            && doc.getUpdatedAt().isAfter(doc.getCreatedAt());

                    return CommentSliceItem.builder()
                            .commentId(doc.getId())
                            .content(doc.getContent())
                            .createdAt(doc.getCreatedAt())
                            .isUpdated(isUpdated)
                            .author(author)
                            .build();
                })
                .toList();

        // nextCursor 생성
        String nextCursor = null;
        if (hasNext) {
            CommentDocument last = content.get(content.size() - 1);
            Cursor.Pos pos = new Cursor.CreatedAtPos(last.getId(), last.getCreatedAt());
            nextCursor = cursorCodec.encode(new Cursor(Cursor.CursorStrategy.RECENT, pos));
        }

        return new PageSlice<>(postId, items, nextCursor, hasNext);
    }

}
