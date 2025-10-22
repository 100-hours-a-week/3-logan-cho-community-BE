package com.example.kaboocampostproject.domain.comment.service;

import com.example.kaboocampostproject.domain.comment.converter.CommentConverter;
import com.example.kaboocampostproject.domain.comment.document.CommentDocument;
import com.example.kaboocampostproject.domain.comment.dto.CommentReqDTO;
import com.example.kaboocampostproject.domain.comment.dto.CommentSliceItem;
import com.example.kaboocampostproject.domain.comment.dto.CommentSliceResDTO;
import com.example.kaboocampostproject.domain.comment.error.CommentErrorCode;
import com.example.kaboocampostproject.domain.comment.error.CommentException;
import com.example.kaboocampostproject.domain.comment.repository.CommentMongoRepository;
import com.example.kaboocampostproject.domain.member.cache.MemberProfileCacheDTO;
import com.example.kaboocampostproject.domain.member.cache.MemberProfileCacheService;
import com.example.kaboocampostproject.domain.s3.util.CloudFrontUtil;
import com.example.kaboocampostproject.global.cursor.Cursor;
import com.example.kaboocampostproject.global.cursor.CursorCodec;
import com.example.kaboocampostproject.global.cursor.PageSlice;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;

@Service
@RequiredArgsConstructor
public class CommentMongoService {

    private static final int PAGE_SIZE = 10;

    private final CommentMongoRepository commentRepository;

    private final MemberProfileCacheService memberProfileCacheService;
    private final CursorCodec cursorCodec;
    private final CloudFrontUtil cloudFrontUtil;

    public void createComment(Long memberId, String postId, CommentReqDTO dto) {
        commentRepository.save(CommentConverter.toEntity(memberId, postId, dto));
    }

    public void updateComment(Long memberId, String commentId, CommentReqDTO dto) {
        boolean update = commentRepository.updateCommentContent(commentId, memberId, dto.content());
        if (update) {
            throw new CommentException(CommentErrorCode.COMMENT_UPDATE_FAIL);
        }
    }

    public void deleteComment(Long memberId, String commentId) {
        boolean update = commentRepository.softDeleteByCommentId(commentId, memberId);
        if (update) {
            throw new CommentException(CommentErrorCode.COMMENT_UPDATE_FAIL);
        }
    }

    // =====================커서로 조회하는 메서드=====================

    // 최신 순 첫페이지
    public CommentSliceResDTO findFirstByPost(String postId) {
        List<CommentDocument> docs =
                commentRepository.findFirstByPostIdOrderByCreatedAtDesc(postId, PAGE_SIZE + 1);

        return buildSlice(postId, docs);
    }

    // 최신 순 다음 페이지
    public CommentSliceResDTO findNextByPost(String postId, String cursorToken) {
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
    private CommentSliceResDTO buildSlice(String postId, List<CommentDocument> docsPlusOne) {
        boolean hasNext = docsPlusOne.size() > PAGE_SIZE;
        List<CommentDocument> content = hasNext ? docsPlusOne.subList(0, PAGE_SIZE) : docsPlusOne;

        if (content.isEmpty()) {
            return CommentSliceResDTO.builder()
                    .cdnBaseUrl(cloudFrontUtil.getDomain())
                    .parentId(postId)
                    .comments(PageSlice.empty())
                    .build();
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
                    return CommentConverter.toSliceItem(doc, p);
                })
                .toList();

        // nextCursor 생성
        String nextCursor = null;
        if (hasNext) {
            CommentDocument last = content.get(content.size() - 1);
            Cursor.Pos pos = new Cursor.CreatedAtPos(last.getId(), last.getCreatedAt());
            nextCursor = cursorCodec.encode(new Cursor(Cursor.CursorStrategy.RECENT, pos));
        }

        PageSlice<CommentSliceItem> pageSlice = new PageSlice<>( items, nextCursor, hasNext);
        // 레퍼로 감싸서 반환 (cdn 도메인 반환 위해서.)
        return CommentSliceResDTO.builder()
                .cdnBaseUrl(cloudFrontUtil.getDomain())
                .parentId(postId)
                .comments(pageSlice)
                .build();

    }

}
