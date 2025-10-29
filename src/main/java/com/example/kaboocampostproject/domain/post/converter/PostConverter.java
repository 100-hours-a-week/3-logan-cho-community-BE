package com.example.kaboocampostproject.domain.post.converter;

import com.example.kaboocampostproject.domain.like.dto.PostLikeStatsDto;
import com.example.kaboocampostproject.domain.member.cache.MemberProfileCacheDTO;
import com.example.kaboocampostproject.domain.post.document.PostDocument;
import com.example.kaboocampostproject.domain.post.dto.req.PostCreatReqDTO;
import com.example.kaboocampostproject.domain.post.dto.res.PostDetailResDTO;
import com.example.kaboocampostproject.domain.post.dto.res.PostSimple;
import com.example.kaboocampostproject.domain.post.dto.res.PostSliceItem;
import jakarta.annotation.Nullable;


public class PostConverter {
    public static PostDocument toEntity(Long memberId, PostCreatReqDTO dto) {
        return PostDocument.builder()
                .authorId(memberId)
                .title(dto.title())
                .content(dto.content())
                .imageObjectKeys(dto.imageObjectKeys())
                .build();
    }

    public static PostDetailResDTO toPostDetail(String cdnBaseUrl, PostDocument post, PostLikeStatsDto postLike, Long authorId, MemberProfileCacheDTO profile, boolean isMine) {
        PostDetailResDTO.AuthorProfile authorProfile =  PostDetailResDTO.AuthorProfile.builder()
                                                        .id(profile!=null ? authorId : null)
                                                        .name(profile!=null ? profile.name() : "(탈퇴한 사용자)")
                                                        .profileImageObjectKey(profile!=null ? profile.profileImageObjectKey() : null)
                                                        .build();

        return PostDetailResDTO.builder()
                .cdnBaseUrl(cdnBaseUrl)
                .title(post.getTitle())
                .content(post.getContent())
                .imageObjectKeys(post.getImageObjectKeys())
                .authorProfile(authorProfile)
                .views(post.getViews())
                .likes(postLike.likeCount())
                .amILiking(postLike.amILike())
                .createdAt(post.getCreatedAt())
                .isUpdated(post.isUpdated())
                .isMine(isMine)
                .build();
    }

    public static PostSliceItem toPostSliceItem(PostSimple post, PostLikeStatsDto postLike, @Nullable MemberProfileCacheDTO memberProfile) {
        PostSliceItem.LikeInfo likeInfo = PostSliceItem.LikeInfo.builder()
                .count(postLike.likeCount())
                .amILike(postLike.amILike())
                .build();

        PostSliceItem.AuthorProfile author = PostSliceItem.AuthorProfile.builder()
                .id(memberProfile!=null ? memberProfile.id() : null)
                .name(memberProfile!=null ? memberProfile.name() : "(탈퇴한 사용자)")
                .profileImageObjectKey(memberProfile!=null ? memberProfile.profileImageObjectKey() : null)
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
