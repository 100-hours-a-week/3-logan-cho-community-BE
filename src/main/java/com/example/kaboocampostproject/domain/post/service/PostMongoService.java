package com.example.kaboocampostproject.domain.post.service;


import com.example.kaboocampostproject.domain.post.config.ImagePipelineProperties;
import com.example.kaboocampostproject.domain.comment.repository.CommentMongoRepository;
import com.example.kaboocampostproject.domain.like.dto.PostLikeStatsDto;
import com.example.kaboocampostproject.domain.post.dto.message.AsyncImageJobMessage;
import com.example.kaboocampostproject.domain.like.entity.PostLike;
import com.example.kaboocampostproject.domain.like.repository.PostLikeRepository;
import com.example.kaboocampostproject.domain.member.cache.MemberProfileCacheDTO;
import com.example.kaboocampostproject.domain.member.cache.MemberProfileCacheService;
import com.example.kaboocampostproject.domain.post.converter.PostConverter;
import com.example.kaboocampostproject.domain.post.document.ImageJobProcessedDocument;
import com.example.kaboocampostproject.domain.post.document.PostDocument;
import com.example.kaboocampostproject.domain.post.dto.req.AsyncImageJobCallbackReqDTO;
import com.example.kaboocampostproject.domain.post.dto.req.PostCreatReqDTO;
import com.example.kaboocampostproject.domain.post.dto.req.PostUpdateReqDTO;
import com.example.kaboocampostproject.domain.post.dto.res.PostCreateResDTO;
import com.example.kaboocampostproject.domain.post.dto.res.PostDetailResDTO;
import com.example.kaboocampostproject.domain.post.dto.res.PostSimple;
import com.example.kaboocampostproject.domain.post.dto.res.PostSliceItem;
import com.example.kaboocampostproject.domain.post.dto.res.PostSliceResDTO;
import com.example.kaboocampostproject.domain.post.error.PostErrorCode;
import com.example.kaboocampostproject.domain.post.error.PostException;
import com.example.kaboocampostproject.domain.post.enums.PostImageStatus;
import com.example.kaboocampostproject.domain.post.repository.PostMongoRepository;
import com.example.kaboocampostproject.domain.post.repository.ImageJobProcessedRepository;
import com.example.kaboocampostproject.domain.s3.service.S3Service;
import com.example.kaboocampostproject.domain.s3.util.CloudFrontUtil;
import com.example.kaboocampostproject.domain.s3.util.S3Util;
import com.example.kaboocampostproject.global.cursor.Cursor;
import com.example.kaboocampostproject.global.cursor.CursorCodec;
import com.example.kaboocampostproject.global.cursor.PageSlice;
import com.example.kaboocampostproject.global.error.CustomException;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
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
    private final ImageProcessingService imageProcessingService;
    private final ImageJobPublisher imageJobPublisher;
    private final ImageJobOutboxService imageJobOutboxService;
    private final ImageJobProcessedRepository imageJobProcessedRepository;
    private final ImagePipelineProperties imagePipelineProperties;

    private static final int PAGE_SIZE = 10;
    private final CloudFrontUtil cloudFrontUtil;

    public PostCreateResDTO create(Long authorId, PostCreatReqDTO postCreatReqDTO) {
        List<String> tempImageKeys = safeList(postCreatReqDTO.imageObjectKeys());
        tempImageKeys.forEach(s3Service::verifyS3Upload);

        if (tempImageKeys.isEmpty()) {
            PostDocument post = buildCompletedPost(authorId, postCreatReqDTO, List.of(), List.of(), List.of());
            postRepository.save(post);
            return PostConverter.toPostCreate(post);
        }

        PostDocument post = buildPendingPost(authorId, postCreatReqDTO, tempImageKeys);

        if (imagePipelineProperties.isAsyncEnabled()) {
            if (imagePipelineProperties.isOutboxEnabled()) {
                imageJobOutboxService.savePostWithOutbox(post, this::buildAsyncMessage);
            } else {
                postRepository.save(post);
                maybeInjectFailureAfterSaveBeforePublish(postCreatReqDTO);
                imageJobPublisher.publish(buildAsyncMessage(post));
            }
            return PostConverter.toPostCreate(post);
        }

        postRepository.save(post);
        try {
            ImageProcessingService.ProcessedImages processedImages = imageProcessingService.process(tempImageKeys);
            applyProcessedImages(post, processedImages);
            postRepository.save(post);
            return PostConverter.toPostCreate(post);
        } catch (RuntimeException e) {
            post.setImageStatus(PostImageStatus.FAILED);
            post.setFailureReason(resolveFailureReason(e));
            postRepository.save(post);
            throw e;
        }
    }

    @Transactional("mongoTransactionManager")
    public void completeAsyncImageJob(String postId, AsyncImageJobCallbackReqDTO request) {
        PostDocument post = postRepository.findByIdAndDeletedAtIsNull(postId)
                .orElseThrow(() -> new PostException(PostErrorCode.POST_NOT_FOUND));

        if (post.getImageJobId() == null || !post.getImageJobId().equals(request.imageJobId())) {
            throw new PostException(PostErrorCode.POST_IMAGE_JOB_MISMATCH);
        }

        if (imagePipelineProperties.isIdempotencyEnabled()) {
            if (!claimCallbackProcessing(postId, request)) {
                return;
            }
        }

        if (request.imageStatus() == PostImageStatus.COMPLETED) {
            post.setFinalImageKeys(safeList(request.finalImageKeys()));
            post.setThumbnailKeys(safeList(request.thumbnailKeys()));
            post.setImageObjectKeys(safeList(request.finalImageKeys()));
            post.setImageStatus(PostImageStatus.COMPLETED);
            post.setFailureReason(null);
            post.setCompletedAt(Instant.now());
            postRepository.save(post);
            return;
        }

        post.setImageStatus(PostImageStatus.FAILED);
        post.setFailureReason(request.failureReason());
        post.setCompletedAt(Instant.now());
        postRepository.save(post);
    }

    private boolean claimCallbackProcessing(String postId, AsyncImageJobCallbackReqDTO request) {
        ImageJobProcessedDocument existing = imageJobProcessedRepository
                .findByImageJobId(request.imageJobId())
                .orElse(null);

        if (existing != null) {
            existing.markDuplicateCallback();
            imageJobProcessedRepository.save(existing);
            return false;
        }

        try {
            imageJobProcessedRepository.save(
                    ImageJobProcessedDocument.builder()
                            .imageJobId(request.imageJobId())
                            .postId(postId)
                            .imageStatus(request.imageStatus())
                            .sideEffectApplyCount(1)
                            .callbackReceiveCount(1)
                            .duplicateIgnoredCount(0)
                            .failureReason(request.failureReason())
                            .build()
            );
            return true;
        } catch (DuplicateKeyException ignored) {
            ImageJobProcessedDocument duplicate = imageJobProcessedRepository
                    .findByImageJobId(request.imageJobId())
                    .orElse(null);
            if (duplicate != null) {
                duplicate.markDuplicateCallback();
                imageJobProcessedRepository.save(duplicate);
            }
            return false;
        }
    }

    private void maybeInjectFailureAfterSaveBeforePublish(PostCreatReqDTO request) {
        if (!imagePipelineProperties.isFailAfterSaveBeforePublishEnabled()) {
            return;
        }

        String title = request.title();
        String prefix = imagePipelineProperties.getFailAfterSaveTitlePrefix();
        if (title == null || prefix == null || prefix.isBlank()) {
            return;
        }

        if (title.startsWith(prefix)) {
            throw new IllegalStateException("fault injection: fail after save before publish");
        }
    }

    private List<String> calculateRemaining(List<String> oldImages, List<String> addedImages, List<String> removedImages) {
        List<String> result = oldImages.stream().filter(s -> !removedImages.contains(s))
                .collect(Collectors.toCollection(ArrayList::new));

        result.addAll(addedImages);
        return result;
    }
    // 게시물 수정
    public void updatePost(Long memberId, String postId, PostUpdateReqDTO req) {
        PostDocument post = postRepository.findByIdAndDeletedAtIsNull(postId)
                .orElseThrow(() -> new PostException(PostErrorCode.POST_NOT_FOUND));

        if (!post.getAuthorId().equals(memberId)) {
            throw new PostException(PostErrorCode.POST_AUTHOR_NOT_MATCH);
        }

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


        List<String> oldImages = safeList(post.getImageObjectKeys());
        List<String> oldThumbnails = safeList(post.getThumbnailKeys());
        List<String> oldTempImages = safeList(post.getTempImageKeys());

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

        List<String> remainingImages = calculateRemaining(oldImages, List.of(), removedImages);
        List<String> remainingThumbnails = removeByReference(oldImages, oldThumbnails, removedImages);
        List<String> deletedThumbnails = findRemovedTargets(oldImages, oldThumbnails, removedImages);

        List<String> newFinalImages = new ArrayList<>();
        List<String> newThumbnailImages = new ArrayList<>();
        if (isImageAdded) {
            ImageProcessingService.ProcessedImages processedImages = imageProcessingService.process(addedImages);
            newFinalImages = processedImages.finalImageKeys();
            newThumbnailImages = processedImages.thumbnailKeys();
            oldTempImages.addAll(processedImages.tempImageKeys());
        }

        if (req.title() != null) post.setTitle(req.title());
        if (req.content() != null) post.setContent(req.content());

        remainingImages.addAll(newFinalImages);
        remainingThumbnails.addAll(newThumbnailImages);

        post.setTempImageKeys(oldTempImages);
        post.setFinalImageKeys(remainingImages);
        post.setThumbnailKeys(remainingThumbnails);
        post.setImageObjectKeys(remainingImages);
        post.setImageStatus(PostImageStatus.COMPLETED);
        post.setFailureReason(null);
        if (isImageAdded || isImageRemoved) {
            post.setCompletedAt(Instant.now());
            post.setImageJobId(UUID.randomUUID().toString());
        }

        postRepository.save(post);

        removedImages.forEach(s3Util::delete);
        deletedThumbnails.forEach(s3Util::delete);

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

        MemberProfileCacheDTO memberProfileCacheDTO = memberProfileCacheService.getProfile(post.getAuthorId());

        // view 증가(로컬 map)
        postViewService.incrementViewCount(postId);

        boolean isMine = memberId.equals(post.getAuthorId());

        return PostConverter.toPostDetail(cloudFrontUtil.getDomain(), post, postLikeState, post.getAuthorId(), memberProfileCacheDTO, isMine);
    }

    // 게시물 좋아요
    public void likePost(Long memberId, String postId) {
        boolean isAlreadyLike = postLikeRepository.existsByMemberIdAndPostId(memberId, postId);
        if(isAlreadyLike) {
            return;
        }
        PostLike postLike = PostLike.of(memberId, postId);
        postLikeRepository.save(postLike);
    }

    // 게시물 좋아요
    public void unLikePost(Long memberId, String postId) {
        PostLike postLike = postLikeRepository.findByMemberIdAndPostId(memberId, postId);
        if(postLike == null) {
            return;
        }
        postLikeRepository.delete(postLike);
    }



    // =====================커서로 조회하는 메서드=====================

    // 첫 페이지 조회
    public PostSliceResDTO findFirst(Long memberId, Cursor.CursorStrategy strategy) {
        List<PostSimple> posts = switch (strategy) {
            case RECENT -> postRepository.findFirstByCreatedAt(PAGE_SIZE + 1);
            case POPULAR -> postRepository.findFirstByView(PAGE_SIZE + 1);
        };

        return buildPageSlice(memberId, posts, strategy);
    }

    // 다음 페이지 조회
    public PostSliceResDTO findNext(Long memberId, String cursorToken) {
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

    private PostDocument buildPendingPost(Long authorId, PostCreatReqDTO request, List<String> tempImageKeys) {
        return PostDocument.builder()
                .authorId(authorId)
                .title(request.title())
                .content(request.content())
                .imageStatus(PostImageStatus.PENDING)
                .imageJobId(UUID.randomUUID().toString())
                .tempImageKeys(tempImageKeys)
                .finalImageKeys(List.of())
                .thumbnailKeys(List.of())
                .imageObjectKeys(List.of())
                .build();
    }

    private PostDocument buildCompletedPost(Long authorId, PostCreatReqDTO request,
                                            List<String> tempImageKeys,
                                            List<String> finalImageKeys,
                                            List<String> thumbnailKeys) {
        return PostDocument.builder()
                .authorId(authorId)
                .title(request.title())
                .content(request.content())
                .imageStatus(PostImageStatus.COMPLETED)
                .imageJobId(tempImageKeys.isEmpty() ? null : UUID.randomUUID().toString())
                .tempImageKeys(tempImageKeys)
                .finalImageKeys(finalImageKeys)
                .thumbnailKeys(thumbnailKeys)
                .imageObjectKeys(finalImageKeys)
                .completedAt(Instant.now())
                .build();
    }

    private void applyProcessedImages(PostDocument post, ImageProcessingService.ProcessedImages processedImages) {
        post.setTempImageKeys(processedImages.tempImageKeys());
        post.setFinalImageKeys(processedImages.finalImageKeys());
        post.setThumbnailKeys(processedImages.thumbnailKeys());
        post.setImageObjectKeys(processedImages.finalImageKeys());
        post.setImageStatus(PostImageStatus.COMPLETED);
        post.setFailureReason(null);
        post.setCompletedAt(Instant.now());
    }

    private String resolveFailureReason(RuntimeException e) {
        if (e instanceof CustomException) {
            return ((CustomException) e).getErrorCode().getCode();
        }
        return PostErrorCode.POST_IMAGE_PROCESSING_FAILED.getCode();
    }

    private List<String> removeByReference(List<String> baseKeys, List<String> targetKeys, List<String> removedBaseKeys) {
        List<String> remaining = new ArrayList<>();
        for (int i = 0; i < targetKeys.size(); i++) {
            String baseKey = i < baseKeys.size() ? baseKeys.get(i) : null;
            if (baseKey != null && removedBaseKeys.contains(baseKey)) {
                continue;
            }
            remaining.add(targetKeys.get(i));
        }
        return remaining;
    }

    private List<String> findRemovedTargets(List<String> baseKeys, List<String> targetKeys, List<String> removedBaseKeys) {
        List<String> removed = new ArrayList<>();
        for (int i = 0; i < targetKeys.size(); i++) {
            String baseKey = i < baseKeys.size() ? baseKeys.get(i) : null;
            if (baseKey != null && removedBaseKeys.contains(baseKey)) {
                removed.add(targetKeys.get(i));
            }
        }
        return removed;
    }

    private List<String> safeList(List<String> values) {
        return values == null ? new ArrayList<>() : new ArrayList<>(values);
    }

    private AsyncImageJobMessage buildAsyncMessage(PostDocument post) {
        String callbackBaseUrl = imagePipelineProperties.getCallbackBaseUrl();
        if (callbackBaseUrl == null || callbackBaseUrl.isBlank()) {
            throw new IllegalStateException("image pipeline callback base url is missing");
        }

        return new AsyncImageJobMessage(
                post.getImageJobId(),
                post.getId(),
                s3Util.getBucket(),
                List.copyOf(safeList(post.getTempImageKeys())),
                "%s/api/posts/internal/image-jobs/%s".formatted(callbackBaseUrl, post.getId()),
                Instant.now()
        );
    }

    // 멤버프로필, like 개수 등 부가정보 가져와서 PageSlice 생성하기
    private PostSliceResDTO buildPageSlice(Long memberId, List<PostSimple> posts, Cursor.CursorStrategy strategy) {
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
            return PostSliceResDTO.builder()
                    .cdnBaseUrl(cloudFrontUtil.getDomain())
                    .posts(PageSlice.empty())
                    .build();
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
                    // 좋아요 매칭
                    PostLikeStatsDto like = likeMap.getOrDefault(
                            post.postId(),
                            new PostLikeStatsDto(post.postId(), 0L, false)
                    );
                    if (post.authorId()==null){
                        return PostConverter.toPostSliceItem(post, like, null);
                    }
                    // 프로필 매칭
                    MemberProfileCacheDTO authorProfile = authorProfiles.get(post.authorId());
                    // 병합
                    return PostConverter.toPostSliceItem(post, like, authorProfile);
                })
                .toList();

        PageSlice<PostSliceItem> pageSlice = new PageSlice<>(items, nextCursor, hasNext);

        return PostSliceResDTO.builder()
                .cdnBaseUrl(cloudFrontUtil.getDomain())
                .posts(pageSlice)
                .build();
    }

}
