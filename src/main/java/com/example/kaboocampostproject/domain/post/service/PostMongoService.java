package com.example.kaboocampostproject.domain.post.service;


import com.example.kaboocampostproject.domain.comment.repository.CommentMongoRepository;
import com.example.kaboocampostproject.domain.like.dto.PostLikeStatsDto;
import com.example.kaboocampostproject.domain.like.repository.PostLikeRepository;
import com.example.kaboocampostproject.domain.member.cache.MemberProfileCacheDTO;
import com.example.kaboocampostproject.domain.member.cache.MemberProfileCacheService;
import com.example.kaboocampostproject.domain.post.converter.PostConverter;
import com.example.kaboocampostproject.domain.post.document.PostDocument;
import com.example.kaboocampostproject.domain.post.dto.req.PostCreatReqDTO;
import com.example.kaboocampostproject.domain.post.dto.req.PostUpdateReqDTO;
import com.example.kaboocampostproject.domain.post.dto.res.PostDetailResDTO;
import com.example.kaboocampostproject.domain.post.dto.res.PostSimple;
import com.example.kaboocampostproject.domain.post.dto.res.PostSliceItem;
import com.example.kaboocampostproject.domain.post.error.PostErrorCode;
import com.example.kaboocampostproject.domain.post.error.PostException;
import com.example.kaboocampostproject.domain.post.repository.PostMongoRepository;
import com.example.kaboocampostproject.domain.s3.service.S3Service;
import com.example.kaboocampostproject.domain.s3.util.S3Util;
import com.example.kaboocampostproject.global.cursor.Cursor;
import com.example.kaboocampostproject.global.cursor.CursorCodec;
import com.example.kaboocampostproject.global.cursor.PageSlice;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;


@Service
@RequiredArgsConstructor
public class PostMongoService {

    private final PostMongoRepository postRepository;
    private final PostLikeRepository postLikeRepository;
    private final CommentMongoRepository commentRepository;
    private final PostViewService postViewService;
    private final MemberProfileCacheService memberProfileCacheService;
    private final CursorCodec codec;
    private final S3Service s3Service;
    private final S3Util s3Util;

    private static final int PAGE_SIZE = 10;

    public void create(Long authorId, PostCreatReqDTO postCreatReqDTO) {
        PostDocument post = PostConverter.toEntity(authorId, postCreatReqDTO);
        // 이미지 존재 시 업로드 검증
        if (postCreatReqDTO.imageObjectKeys() != null && !postCreatReqDTO.imageObjectKeys().isEmpty()) {
            postCreatReqDTO.imageObjectKeys().forEach(s3Service::verifyS3Upload);
        }
        postRepository.save(post);
    }

    private List<String> calculateRemaining(List<String> oldImages, List<String> addedImages, List<String> removedImages) {
        List<String> result = oldImages.stream().filter(s -> !removedImages.contains(s))
                .collect(Collectors.toCollection(ArrayList::new));

        result.addAll(addedImages);
        return result;
    }
    // 게시물 수정
    public void updatePost(Long memberId, String postId, PostUpdateReqDTO req) {

        // 추가, 삭제 요청된 이미지 오브젝트 키
        List<String> addedImages = (req.addedImageObjectKeys()!=null)
                ? req.addedImageObjectKeys()
                : new ArrayList<>();
        List<String> removedImages = (req.removedImageObjectKeys()!=null)
                ? req.removedImageObjectKeys()
                : new ArrayList<>();

        // 존재여부
        boolean isImageAdded = !addedImages.isEmpty();
        boolean isImageRemoved = !removedImages.isEmpty();


        List<String> oldImages = (isImageAdded || isImageRemoved)
                ? postRepository.findImageObjectKeys(postId, memberId)
                : new ArrayList<>();


        // 업로드 검증
        if (isImageAdded) {

            int imageCnt = oldImages.size()
                            + addedImages.size()
                            - removedImages.size();

            if (imageCnt > 3) {
                throw new  PostException(PostErrorCode.TOO_MANY_IMAGES);
            }

            addedImages.forEach(s3Service::verifyS3Upload);
        }
        // 삭제 체킹
        if (isImageRemoved) {
            removedImages.forEach(image -> {
                if (!oldImages.contains(image))
                    throw new PostException(PostErrorCode.POST_IMAGE_NOT_FOUND);
            });
        }

        List<String> remainingImages = calculateRemaining(oldImages, addedImages, removedImages);

        // DB 업데이트
        boolean updated = postRepository.updatePostFields(memberId, postId, req, remainingImages);
        if (!updated) throw new PostException(PostErrorCode.POST_UPDATED_FAIL);

        // 삭제할 이미지 있다면 삭제
        removedImages.forEach(s3Util::delete);

        // 댓글도 모두 소프트딜리트
        commentRepository.softDeleteByPostId(postId);
    }

    // 게시물 삭제
    public void deletePost(Long memberId, String postId) {

        boolean idUpdated = postRepository.softDelete(postId, memberId);
        if (!idUpdated) throw new PostException(PostErrorCode.POST_UPDATED_FAIL);

        //기존 쿼리. 부하테스트 시 속도비교 예정
        /*PostDocument post = postRepository.findByIdAndDeletedAtIsNull(postId)
                .orElseThrow(() -> new PostException(PostErrorCode.POST_NOT_FOUND));
        // 작성자 검증
        if (!post.getAuthorId().equals(memberId)) {
            throw new PostException(PostErrorCode.POST_AUTHOR_NOT_MATCH);
        }
        // 소프트딜리트
        post.setDeletedAt(Instant.now());
        postRepository.save(post);*/
    }

    // 게시물 상세조회
    public PostDetailResDTO getById(String postId, Long memberId) {

        PostDocument post = postRepository.findByIdAndDeletedAtIsNull(postId)
                .orElseThrow(() -> new PostException(PostErrorCode.POST_NOT_FOUND));

        //like 정보 가져오기 (내가 좋아요하는지 여부도)
        PostLikeStatsDto postLikeState = postLikeRepository
                .findPostLikeStatsByPostId(postId, memberId)
                .orElse(new PostLikeStatsDto(postId, 0L, false));

        // view 증가(로컬 map)
        postViewService.incrementViewCount(postId);

        return PostConverter.toPostDetail(post, postLikeState);//
    }


    // =====================커서로 조회하는 메서드=====================

    // 첫 페이지 조회
    public PageSlice<PostSliceItem> findFirst(Long memberId, Cursor.CursorStrategy strategy) {
        List<PostSimple> posts = switch (strategy) {
            case RECENT -> postRepository.findFirstByCreatedAt(PAGE_SIZE + 1);
            case POPULAR -> postRepository.findFirstByView(PAGE_SIZE + 1);
        };

        return buildPageSlice(memberId, posts, strategy);
    }

    // 다음 페이지 조회
    public PageSlice<PostSliceItem> findNext(Long memberId, String cursorToken) {
        Cursor cursor = codec.decode(cursorToken);

        List<PostSimple> posts = switch (cursor.strategy()) {
            case RECENT -> {
                Cursor.CreatedAtPos pos = (Cursor.CreatedAtPos) cursor.pos();
                yield postRepository.findNextByCreatedAt(pos.createdAt(), pos.id(), PAGE_SIZE + 1);
            }
            case POPULAR -> {
                Cursor.ViewPos pos = (Cursor.ViewPos) cursor.pos();
                yield postRepository.findNextByView(pos.view(), pos.createdAt(), pos.id(), PAGE_SIZE + 1);
            }
        };

        return buildPageSlice(memberId, posts, cursor.strategy());
    }

    // 멤버프로필, like 개수 등 부가정보 가져와서 PageSlice 생성하기
    private PageSlice<PostSliceItem> buildPageSlice(Long memberId, List<PostSimple> posts, Cursor.CursorStrategy strategy) {
        boolean hasNext = posts.size() > PAGE_SIZE;

        // 마지막 여부 확인위해, 하나 더 가져왔으니 자르기.
        List<PostSimple> content = hasNext ? posts.subList(0, PAGE_SIZE) : posts;

        // 다음 커서 설정
        String nextCursor = null;
        if (hasNext) {
            PostSimple last = content.get(content.size() - 1);
            Cursor.Pos pos = switch (strategy) {
                case RECENT -> new Cursor.CreatedAtPos(last.postId(), last.createdAt());
                case POPULAR -> new Cursor.ViewPos(last.postId(), last.createdAt(), last.views());
            };
            nextCursor = codec.encode(new Cursor(strategy, pos));
        }

        if (content.isEmpty()) {
            return new PageSlice<>(null, List.of(), nextCursor, false);
        }


        List<String> postIds = content.stream().map(PostSimple::postId).toList();
        List<Long> authorIds = content.stream().map(PostSimple::authorId).distinct().toList();

        // Redis-> MySql 순서로 작성자 프로필 조회
        Map<Long, MemberProfileCacheDTO> authorProfiles = memberProfileCacheService.getProfiles(authorIds);

        // MySql에서 좋아요 개수, 내가 좋아요했는지 조회
        List<PostLikeStatsDto> likeStats = postLikeRepository.findPostLikeStats(postIds, memberId);
        Map<String, PostLikeStatsDto> likeMap = likeStats.stream()
                .collect(Collectors.toMap(PostLikeStatsDto::postId, dto -> dto));

        //PostSliceItem로 병합
        List<PostSliceItem> items = content.stream()
                .map(post -> {
                    PostLikeStatsDto like = likeMap.getOrDefault(
                            post.postId(),
                            new PostLikeStatsDto(post.postId(), 0L, false)
                    );
                    MemberProfileCacheDTO authorProfile = authorProfiles.get(post.authorId());
                    return PostConverter.toPostSliceItem(post, like, authorProfile);
                })
                .toList();

        return new PageSlice<>(null, items, nextCursor, hasNext);
    }

}
