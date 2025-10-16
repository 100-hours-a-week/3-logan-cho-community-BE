package com.example.kaboocampostproject.domain.post.repository;

import com.example.kaboocampostproject.domain.post.dto.req.PostUpdateReqDTO;
import com.example.kaboocampostproject.domain.post.dto.res.PostSimple;


import java.time.Instant;
import java.util.List;

public interface PostCustomRepository {

    List<String> findImageObjectKeys(String postId, Long memberId);

    boolean updatePostFields(Long memberId, String postId, PostUpdateReqDTO req, List<String> remainingImages);

    boolean softDelete(String postId, Long memberId);

    // 조회수 증가 (inc)
    void incrementViews(String postId, long count);

    // 최신순 첫 페이지
    List<PostSimple> findFirstByCreatedAt(int sizePlusOne);

    // 최신순 다음 페이지
    List<PostSimple> findNextByCreatedAt(Instant createdAt, String id, int sizePlusOne);

    // 인기순 첫 페이지
    List<PostSimple> findFirstByView(int sizePlusOne);

    // 인기순 다음 페이지
    List<PostSimple> findNextByView(long view, Instant createdAt, String id, int sizePlusOne);
}
