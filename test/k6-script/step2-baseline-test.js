/**
 * Step 2: 베이스라인 성능 측정 테스트 (수정됨)
 */

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Trend, Rate } from 'k6/metrics';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.1/index.js';

// 환경 변수
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const TEST_LABEL = __ENV.TEST_LABEL || 'baseline';

// 테스트 사용자 설정
const TEST_USERS_COUNT = 100;
const TEST_USER_PREFIX = 'perf_testers';
const TEST_USER_PASSWORD = 'Test1234!@#$';

// 커스텀 메트릭
const listPostsDuration = new Trend('baseline_list_posts_duration');
const postDetailDuration = new Trend('baseline_post_detail_duration');
const postNextPageDuration = new Trend('baseline_post_next_page_duration');
const createPostDuration = new Trend('baseline_create_post_duration');
const listCommentsDuration = new Trend('baseline_list_comments_duration');
const commentNextPageDuration = new Trend('baseline_comment_next_page_duration');
const createCommentDuration = new Trend('baseline_create_comment_duration');
const likeActionDuration = new Trend('baseline_like_action_duration');

const listPostsSuccess = new Rate('baseline_list_posts_success');
const postDetailSuccess = new Rate('baseline_post_detail_success');
const postNextPageSuccess = new Rate('baseline_post_next_page_success');
const createPostSuccess = new Rate('baseline_create_post_success');
const listCommentsSuccess = new Rate('baseline_list_comments_success');
const commentNextPageSuccess = new Rate('baseline_comment_next_page_success');
const createCommentSuccess = new Rate('baseline_create_comment_success');
const likeActionSuccess = new Rate('baseline_like_action_success');

// 테스트 설정
export const options = {
    scenarios: {
        constant_load: {
            executor: 'constant-vus',
            vus: 100,
            duration: '5m',
        },
    },
    thresholds: {
        'baseline_list_posts_duration': ['p(50)<1000', 'p(95)<3000', 'p(99)<5000'],
        'baseline_post_detail_duration': ['p(50)<1500', 'p(95)<4000', 'p(99)<6000'],
        'baseline_post_next_page_duration': ['p(50)<1000', 'p(95)<3000', 'p(99)<5000'],
        'baseline_create_post_duration': ['p(50)<2000', 'p(95)<5000', 'p(99)<8000'],
        'baseline_list_comments_duration': ['p(50)<1000', 'p(95)<3000', 'p(99)<5000'],
        'baseline_comment_next_page_duration': ['p(50)<1000', 'p(95)<3000', 'p(99)<5000'],
        'baseline_create_comment_duration': ['p(50)<1500', 'p(95)<4000', 'p(99)<6000'],
        'baseline_like_action_duration': ['p(50)<500', 'p(95)<2000', 'p(99)<3000'],
        'http_req_failed': ['rate<0.05'],
    },
};

// Setup: 테스트 사용자 생성 및 로그인
export function setup() {
    console.log('=== Step 2: 베이스라인 성능 측정 시작 ===');
    console.log(`대상 서버: ${BASE_URL}`);
    console.log(`테스트 레이블: ${TEST_LABEL}`);

    console.log(`\n2. 테스트 사용자 ${TEST_USERS_COUNT}명 생성 중...`);
    const testUsers = [];

    for (let i = 0; i < TEST_USERS_COUNT; i++) {
        const email = `${TEST_USER_PREFIX}_${i}@test.com`;

        // 회원가입
        const signupPayload = JSON.stringify({
            email: email,
            password: TEST_USER_PASSWORD,
            name: `성능테스터${i}`,
            imageObjectKey: null,
            emailVerifiedToken: 'dummy_token'
        });

        http.post(
            `${BASE_URL}/api/members`,
            signupPayload,
            { headers: { 'Content-Type': 'application/json' } }
        );

        // 로그인하여 토큰 획득
        const loginPayload = JSON.stringify({
            email: email,
            password: TEST_USER_PASSWORD,
            deviceId: `device_perf_${i}_${Date.now()}`
        });

        const loginRes = http.post(
            `${BASE_URL}/api/auth`,
            loginPayload,
            { headers: { 'Content-Type': 'application/json' } }
        );

        if (loginRes.status === 200) {
            const loginData = JSON.parse(loginRes.body);
            const accessToken = loginData.data?.accessJwt;

            if (accessToken) {
                testUsers.push({
                    index: i,
                    email: email,
                    accessToken: accessToken,
                });

                if (i % 10 === 9) {
                    console.log(`  ✓ ${i + 1}명 생성 및 로그인 완료`);
                }
            }
        } else {
            console.error(`  ✗ 사용자 ${i} 로그인 실패`);
        }

        sleep(0.05);
    }

    console.log(`✓ 테스트 사용자 준비 완료: ${testUsers.length}명`);
    console.log('\n3. 베이스라인 측정 시작\n');

    return { testUsers: testUsers };
}

// Main: 성능 측정
export default function(data) {
    const testUsers = data.testUsers;

    if (!testUsers || testUsers.length === 0) {
        console.error('테스트 사용자가 없습니다.');
        sleep(1);
        return;
    }

    const userIndex = (__VU - 1) % testUsers.length;
    const user = testUsers[userIndex];

    const headers = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${user.accessToken}`,
    };

    // 1. 게시글 목록 조회 (항상 수행)
    let firstPagePosts = [];
    let nextCursor = null;

    group('게시글 목록 조회', () => {
        const startTime = Date.now();
        const res = http.get(`${BASE_URL}/api/posts?strategy=RECENT`, { headers });
        const duration = Date.now() - startTime;

        listPostsDuration.add(duration);
        const success = check(res, { '상태 200': (r) => r.status === 200 });
        listPostsSuccess.add(success);

        if (res.status === 200) {
            const listData = JSON.parse(res.body);
            firstPagePosts = listData.data?.posts?.items || [];
            nextCursor = listData.data?.posts?.nextCursor;
        }
    });

    sleep(0.3);

    // 2. 게시글 다음 페이지 조회 (커서 있으면 30% 확률)
    if (nextCursor && Math.random() < 0.3) {
        group('게시글 다음 페이지 조회', () => {
            const startTime = Date.now();
            const res = http.get(`${BASE_URL}/api/posts?cursor=${encodeURIComponent(nextCursor)}&strategy=RECENT`, { headers });
            const duration = Date.now() - startTime;

            postNextPageDuration.add(duration);
            const success = check(res, { '상태 200': (r) => r.status === 200 });
            postNextPageSuccess.add(success);
        });

        sleep(0.3);
    }

    // 3. 게시글 상세 조회 (항상 수행)
    let selectedPostId = null;

    if (firstPagePosts.length > 0) {
        group('게시글 상세 조회', () => {
            selectedPostId = firstPagePosts[Math.floor(Math.random() * firstPagePosts.length)].postId;

            const startTime = Date.now();
            const detailRes = http.get(`${BASE_URL}/api/posts/${selectedPostId}`, { headers });
            const duration = Date.now() - startTime;

            postDetailDuration.add(duration);
            const success = check(detailRes, { '상태 200': (r) => r.status === 200 });
            postDetailSuccess.add(success);
        });

        sleep(0.5);
    }

    // 4. 댓글 목록 조회 (게시글 선택됐으면 50% 확률)
    let commentNextCursor = null;

    if (selectedPostId && Math.random() < 0.5) {
        group('댓글 목록 조회', () => {
            const startTime = Date.now();
            const res = http.get(`${BASE_URL}/api/posts/${selectedPostId}/comments`, { headers });
            const duration = Date.now() - startTime;

            listCommentsDuration.add(duration);
            const success = check(res, { '상태 200': (r) => r.status === 200 });
            listCommentsSuccess.add(success);

            if (res.status === 200) {
                const commentData = JSON.parse(res.body);
                commentNextCursor = commentData.data?.comments?.nextCursor;
            }
        });

        sleep(0.3);

        // 5. 댓글 다음 페이지 조회 (커서 있으면 30% 확률)
        if (commentNextCursor && Math.random() < 0.3) {
            group('댓글 다음 페이지 조회', () => {
                const startTime = Date.now();
                const res = http.get(`${BASE_URL}/api/posts/${selectedPostId}/comments?cursor=${encodeURIComponent(commentNextCursor)}`, { headers });
                const duration = Date.now() - startTime;

                commentNextPageDuration.add(duration);
                const success = check(res, { '상태 200': (r) => r.status === 200 });
                commentNextPageSuccess.add(success);
            });

            sleep(0.3);
        }
    }

    // 6. 게시글 작성 (10% 확률)
    if (Math.random() < 0.1) {
        group('게시글 작성', () => {
            const payload = JSON.stringify({
                title: `성능테스트 게시글 ${Date.now()}`,
                content: '베이스라인 성능 측정용 게시글입니다.',
                imageObjectKeys: []
            });

            const startTime = Date.now();
            const res = http.post(`${BASE_URL}/api/posts`, payload, { headers });
            const duration = Date.now() - startTime;

            createPostDuration.add(duration);
            const success = check(res, { '상태 200': (r) => r.status === 200 });
            createPostSuccess.add(success);
        });

        sleep(0.5);
    }

    // 7. 댓글 작성 (15% 확률)
    if (selectedPostId && Math.random() < 0.15) {
        group('댓글 작성', () => {
            const payload = JSON.stringify({
                content: `성능테스트 댓글 ${Date.now()}`
            });

            const startTime = Date.now();
            const res = http.post(`${BASE_URL}/api/posts/${selectedPostId}/comments`, payload, { headers });
            const duration = Date.now() - startTime;

            createCommentDuration.add(duration);
            const success = check(res, { '상태 200': (r) => r.status === 200 });
            createCommentSuccess.add(success);
        });

        sleep(0.5);
    }

    // 8. 좋아요/취소 (10% 확률)
    if (selectedPostId && Math.random() < 0.1) {
        group('좋아요 액션', () => {
            // 상세 조회해서 현재 좋아요 상태 확인
            const detailRes = http.get(`${BASE_URL}/api/posts/${selectedPostId}`, { headers });

            if (detailRes.status === 200) {
                const detailData = JSON.parse(detailRes.body);
                const amILiking = detailData.data?.amILiking;

                const startTime = Date.now();
                let res;

                if (amILiking) {
                    // 좋아요 취소 (DELETE)
                    res = http.del(`${BASE_URL}/api/posts/${selectedPostId}/likes`, null, { headers });
                } else {
                    // 좋아요 (POST)
                    res = http.post(`${BASE_URL}/api/posts/${selectedPostId}/likes`, null, { headers });
                }

                const duration = Date.now() - startTime;

                likeActionDuration.add(duration);
                const success = check(res, { '상태 200': (r) => r.status === 200 });
                likeActionSuccess.add(success);
            }
        });

        sleep(0.5);
    }

    sleep(Math.random() * 2 + 1);
}

// Summary: 결과 저장
export function handleSummary(data) {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const filename = `performance-results/${TEST_LABEL}-${timestamp}.json`;

    console.log('\n=== 베이스라인 성능 측정 결과 ===\n');

    const metrics = data.metrics;

    console.log('📊 응답 시간 (ms):');
    console.log(`  게시글 목록: p50=${metrics.baseline_list_posts_duration?.values?.['p(50)']?.toFixed(2)}ms, p95=${metrics.baseline_list_posts_duration?.values?.['p(95)']?.toFixed(2)}ms`);
    console.log(`  게시글 다음페이지: p50=${metrics.baseline_post_next_page_duration?.values?.['p(50)']?.toFixed(2)}ms, p95=${metrics.baseline_post_next_page_duration?.values?.['p(95)']?.toFixed(2)}ms`);
    console.log(`  게시글 상세: p50=${metrics.baseline_post_detail_duration?.values?.['p(50)']?.toFixed(2)}ms, p95=${metrics.baseline_post_detail_duration?.values?.['p(95)']?.toFixed(2)}ms`);
    console.log(`  댓글 목록: p50=${metrics.baseline_list_comments_duration?.values?.['p(50)']?.toFixed(2)}ms, p95=${metrics.baseline_list_comments_duration?.values?.['p(95)']?.toFixed(2)}ms`);
    console.log(`  댓글 다음페이지: p50=${metrics.baseline_comment_next_page_duration?.values?.['p(50)']?.toFixed(2)}ms, p95=${metrics.baseline_comment_next_page_duration?.values?.['p(95)']?.toFixed(2)}ms`);
    console.log(`  게시글 작성: p50=${metrics.baseline_create_post_duration?.values?.['p(50)']?.toFixed(2)}ms, p95=${metrics.baseline_create_post_duration?.values?.['p(95)']?.toFixed(2)}ms`);
    console.log(`  댓글 작성: p50=${metrics.baseline_create_comment_duration?.values?.['p(50)']?.toFixed(2)}ms, p95=${metrics.baseline_create_comment_duration?.values?.['p(95)']?.toFixed(2)}ms`);
    console.log(`  좋아요 액션: p50=${metrics.baseline_like_action_duration?.values?.['p(50)']?.toFixed(2)}ms, p95=${metrics.baseline_like_action_duration?.values?.['p(95)']?.toFixed(2)}ms`);

    console.log('\n✅ 성공률:');
    console.log(`  게시글 목록: ${(metrics.baseline_list_posts_success?.values?.rate * 100)?.toFixed(2)}%`);
    console.log(`  게시글 다음페이지: ${(metrics.baseline_post_next_page_success?.values?.rate * 100)?.toFixed(2)}%`);
    console.log(`  게시글 상세: ${(metrics.baseline_post_detail_success?.values?.rate * 100)?.toFixed(2)}%`);
    console.log(`  댓글 목록: ${(metrics.baseline_list_comments_success?.values?.rate * 100)?.toFixed(2)}%`);
    console.log(`  댓글 다음페이지: ${(metrics.baseline_comment_next_page_success?.values?.rate * 100)?.toFixed(2)}%`);
    console.log(`  게시글 작성: ${(metrics.baseline_create_post_success?.values?.rate * 100)?.toFixed(2)}%`);
    console.log(`  댓글 작성: ${(metrics.baseline_create_comment_success?.values?.rate * 100)?.toFixed(2)}%`);
    console.log(`  좋아요 액션: ${(metrics.baseline_like_action_success?.values?.rate * 100)?.toFixed(2)}%`);

    console.log(`\n📁 결과 저장: ${filename}`);

    return {
        [filename]: JSON.stringify(data, null, 2),
        'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    };
}

// Teardown
export function teardown(data) {
    console.log('\n=== Step 2: 베이스라인 측정 완료 ===');
}