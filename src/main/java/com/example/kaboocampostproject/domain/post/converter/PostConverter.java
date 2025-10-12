package com.example.kaboocampostproject.domain.post.converter;

import com.example.kaboocampostproject.domain.like.dto.PostLikeStatsDto;
import com.example.kaboocampostproject.domain.member.cache.MemberProfileCacheDTO;
import com.example.kaboocampostproject.domain.post.document.PostDocument;
import com.example.kaboocampostproject.domain.post.dto.req.PostCreatReqDTO;
import com.example.kaboocampostproject.domain.post.dto.res.PostDetailResDTO;
import com.example.kaboocampostproject.domain.post.dto.res.PostSimple;
import com.example.kaboocampostproject.domain.post.dto.res.PostSliceItem;

public class PostConverter {
    public static PostDocument toEntity(Long memberId, PostCreatReqDTO dto) {
        return PostDocument.builder()
                .authorId(memberId)
                .title(dto.title())
                .content(dto.content())
                .imageUrls(dto.imageUrls())
                .build();
    }

    public static PostDetailResDTO toPostDetail(PostDocument post, PostLikeStatsDto postLike) {
        return PostDetailResDTO.builder()
                .title(post.getTitle())
                .content(post.getContent())
                .imageUrls(post.getImageUrls())
                .views(post.getViews())
                .likes(postLike.likeCount())
                .amILiking(postLike.amILike())
                .createdAt(post.getCreatedAt())
                .isUpdated(post.getUpdatedAt()!=null)
                .build();
    }

    public static PostSliceItem toPostSliceItem(PostSimple post, PostLikeStatsDto postLike, MemberProfileCacheDTO memberProfile) {
        PostSliceItem.LikeInfo likeInfo = PostSliceItem.LikeInfo.builder()
                .count(postLike.likeCount())
                .amILike(postLike.amILike())
                .build();

        PostSliceItem.AuthorProfile author = PostSliceItem.AuthorProfile.builder()
                .id(memberProfile.id())
                .name(memberProfile.name())
                .profileImageUrl(memberProfile.profileImageUrl())
                .build();

        return PostSliceItem.builder()
                .postId(post.postId())
                .title(post.title())
                .views(post.views())
                .createdAt(post.createdAt())
                .author(author)
                .like(likeInfo)
                .build();
    }
}
