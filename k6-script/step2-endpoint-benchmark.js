/**
 * Step 2: 엔드포인트별 성능 벤치마크
 *
 * 목적: 각 API 엔드포인트의 개별 성능을 측정
 *
 * 실행 방법:
 *   k6 run --env BASE_URL=http://localhost:8080 --env TEST_LABEL=before k6-script/step2-endpoint-benchmark.js
 *
 * 전제 조건:
 *   - Step 1 (step1-seed-background.js)이 먼저 실행되어 배경 데이터가 존재해야 함
 *
 * 특징:
 *   - setup()에서 perf_tester_{i} 패턴으로 Test User 20명 생성
 *   - Access Token 배열을 return하여 테스트에서 사용
 *   - 각 엔드포인트를 순차적으로 개별 벤치마크
 */

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Trend, Rate } from 'k6/metrics';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.1/index.js';

// 각 엔드포인트별 상세 메트릭
const metrics = {
  listPosts: {
    duration: new Trend('endpoint_list_posts_duration'),
    success: new Rate('endpoint_list_posts_success'),
    throughput: new Rate('endpoint_list_posts_throughput'),
  },
  getPostDetail: {
    duration: new Trend('endpoint_get_post_detail_duration'),
    success: new Rate('endpoint_get_post_detail_success'),
    throughput: new Rate('endpoint_get_post_detail_throughput'),
  },
  createPost: {
    duration: new Trend('endpoint_create_post_duration'),
    success: new Rate('endpoint_create_post_success'),
    throughput: new Rate('endpoint_create_post_throughput'),
  },
  likePost: {
    duration: new Trend('endpoint_like_post_duration'),
    success: new Rate('endpoint_like_post_success'),
    throughput: new Rate('endpoint_like_post_throughput'),
  },
  unlikePost: {
    duration: new Trend('endpoint_unlike_post_duration'),
    success: new Rate('endpoint_unlike_post_success'),
    throughput: new Rate('endpoint_unlike_post_throughput'),
  },
  createComment: {
    duration: new Trend('endpoint_create_comment_duration'),
    success: new Rate('endpoint_create_comment_success'),
    throughput: new Rate('endpoint_create_comment_throughput'),
  },
  listComments: {
    duration: new Trend('endpoint_list_comments_duration'),
    success: new Rate('endpoint_list_comments_success'),
    throughput: new Rate('endpoint_list_comments_throughput'),
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const TEST_LABEL = __ENV.TEST_LABEL || 'endpoint-benchmark';

const TEST_USERS_COUNT = 20;
const TEST_USER_PREFIX = 'perf_tester';
const TEST_USER_PASSWORD = 'Test1234!@#$';

// 각 엔드포인트를 개별적으로 벤치마크
export const options = {
  scenarios: {
    list_posts_bench: {
      executor: 'constant-vus',
      exec: 'testListPosts',
      vus: 20,
      duration: '1m',
      startTime: '0s',
      tags: { endpoint: 'list_posts' },
    },
    get_post_detail_bench: {
      executor: 'constant-vus',
      exec: 'testGetPostDetail',
      vus: 20,
      duration: '1m',
      startTime: '1m',
      tags: { endpoint: 'get_post_detail' },
    },
    create_post_bench: {
      executor: 'constant-vus',
      exec: 'testCreatePost',
      vus: 10,
      duration: '1m',
      startTime: '2m',
      tags: { endpoint: 'create_post' },
    },
    like_post_bench: {
      executor: 'constant-vus',
      exec: 'testLikePost',
      vus: 20,
      duration: '1m',
      startTime: '3m',
      tags: { endpoint: 'like_post' },
    },
    create_comment_bench: {
      executor: 'constant-vus',
      exec: 'testCreateComment',
      vus: 15,
      duration: '1m',
      startTime: '4m',
      tags: { endpoint: 'create_comment' },
    },
    list_comments_bench: {
      executor: 'constant-vus',
      exec: 'testListComments',
      vus: 20,
      duration: '1m',
      startTime: '5m',
      tags: { endpoint: 'list_comments' },
    },
  },
  thresholds: {
    'endpoint_list_posts_duration': ['p(95)<2000'],
    'endpoint_get_post_detail_duration': ['p(95)<2500'],
    'endpoint_create_post_duration': ['p(95)<3000'],
    'endpoint_like_post_duration': ['p(95)<1000'],
    'endpoint_create_comment_duration': ['p(95)<2000'],
    'endpoint_list_comments_duration': ['p(95)<2000'],
  },
};

export function setup() {
  console.log('=== Step 2: 엔드포인트별 성능 벤치마크 시작 ===');
  console.log(`테스트 레이블: ${TEST_LABEL}`);
  console.log(`대상 서버: ${BASE_URL}`);

  // 1. 배경 데이터 확인
  console.log('\n1. 배경 데이터 확인 중...');
  const checkRes = http.get(`${BASE_URL}/api/posts?strategy=RECENT`);
  if (checkRes.status !== 200) {
    throw new Error('배경 데이터가 없습니다. step1-seed-background.js를 먼저 실행하세요.');
  }

  const checkData = JSON.parse(checkRes.body);
  const posts = checkData.data?.posts?.content;
  if (!posts || posts.length === 0) {
    throw new Error('게시글이 없습니다. step1-seed-background.js를 먼저 실행하세요.');
  }

  console.log(`✓ 배경 데이터 확인 완료 (게시글 ${posts.length}개 확인)`);

  // 2. 테스트 사용자 생성 및 로그인
  console.log(`\n2. 테스트 사용자 ${TEST_USERS_COUNT}명 생성 중...`);
  const testUsers = [];

  for (let i = 0; i < TEST_USERS_COUNT; i++) {
    const email = `${TEST_USER_PREFIX}_${i}@test.com`;

    // 회원가입
    const signupPayload = JSON.stringify({
      email: email,
      password: TEST_USER_PASSWORD,
      name: `벤치마크테스터${i}`,
      imageObjectKey: null,
      emailVerifiedToken: 'dummy_token'
    });

    const signupRes = http.post(
      `${BASE_URL}/api/members`,
      signupPayload,
      { headers: { 'Content-Type': 'application/json' } }
    );

    if (signupRes.status !== 200) {
      console.warn(`  경고: 사용자 ${i} 생성 실패 (이미 존재할 수 있음)`);
    }

    // 로그인하여 토큰 획득
    const loginPayload = JSON.stringify({
      email: email,
      password: TEST_USER_PASSWORD,
      deviceId: `device_bench_${i}_${Date.now()}`
    });

    const loginRes = http.post(
      `${BASE_URL}/api/auth`,
      loginPayload,
      { headers: { 'Content-Type': 'application/json' } }
    );

    if (loginRes.status === 200) {
      const loginData = JSON.parse(loginRes.body);
      const accessToken = loginData.data?.accessToken;

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
  console.log('\n3. 벤치마크 시작\n');

  return {
    testUsers: testUsers,
    samplePostId: posts[0].postId,
  };
}

// 1. 게시글 목록 조회 벤치마크
export function testListPosts(data) {
  const testUsers = data.testUsers;
  const userIndex = (__VU - 1) % testUsers.length;
  const user = testUsers[userIndex];

  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${user.accessToken}`,
  };

  const strategies = ['RECENT', 'POPULAR'];
  const strategy = strategies[Math.floor(Math.random() * strategies.length)];

  const startTime = Date.now();
  const res = http.get(`${BASE_URL}/api/posts?strategy=${strategy}`, { headers });
  const duration = Date.now() - startTime;

  metrics.listPosts.duration.add(duration);
  const success = check(res, { '상태 200': (r) => r.status === 200 });
  metrics.listPosts.success.add(success);
  metrics.listPosts.throughput.add(1);

  sleep(0.1);
}

// 2. 게시글 상세 조회 벤치마크
export function testGetPostDetail(data) {
  const testUsers = data.testUsers;
  const userIndex = (__VU - 1) % testUsers.length;
  const user = testUsers[userIndex];

  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${user.accessToken}`,
  };

  // 먼저 목록에서 게시글 ID 가져오기
  const listRes = http.get(`${BASE_URL}/api/posts?strategy=RECENT`, { headers });
  if (listRes.status === 200) {
    const listData = JSON.parse(listRes.body);
    const posts = listData.data?.posts?.content;

    if (posts && posts.length > 0) {
      const postId = posts[Math.floor(Math.random() * posts.length)].postId;

      const startTime = Date.now();
      const res = http.get(`${BASE_URL}/api/posts/${postId}`, { headers });
      const duration = Date.now() - startTime;

      metrics.getPostDetail.duration.add(duration);
      const success = check(res, { '상태 200': (r) => r.status === 200 });
      metrics.getPostDetail.success.add(success);
      metrics.getPostDetail.throughput.add(1);
    }
  }

  sleep(0.1);
}

// 3. 게시글 작성 벤치마크
export function testCreatePost(data) {
  const testUsers = data.testUsers;
  const userIndex = (__VU - 1) % testUsers.length;
  const user = testUsers[userIndex];

  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${user.accessToken}`,
  };

  const payload = JSON.stringify({
    title: `벤치마크 게시글 ${Date.now()}`,
    content: `엔드포인트 성능 측정용 게시글 - VU${__VU}`,
    imageObjectKeys: []
  });

  const startTime = Date.now();
  const res = http.post(`${BASE_URL}/api/posts`, payload, { headers });
  const duration = Date.now() - startTime;

  metrics.createPost.duration.add(duration);
  const success = check(res, { '상태 200': (r) => r.status === 200 });
  metrics.createPost.success.add(success);
  metrics.createPost.throughput.add(1);

  sleep(0.2);
}

// 4. 좋아요/취소 벤치마크 (amILiking 확인 후 처리)
export function testLikePost(data) {
  const testUsers = data.testUsers;
  const userIndex = (__VU - 1) % testUsers.length;
  const user = testUsers[userIndex];

  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${user.accessToken}`,
  };

  const listRes = http.get(`${BASE_URL}/api/posts?strategy=POPULAR`, { headers });
  if (listRes.status === 200) {
    const listData = JSON.parse(listRes.body);
    const posts = listData.data?.posts?.content;

    if (posts && posts.length > 0) {
      const postId = posts[Math.floor(Math.random() * posts.length)].postId;

      // 현재 좋아요 상태 확인
      const detailRes = http.get(`${BASE_URL}/api/posts/${postId}`, { headers });

      if (detailRes.status === 200) {
        const detailData = JSON.parse(detailRes.body);
        const amILiking = detailData.data?.amILiking;

        // 좋아요
        let startTime = Date.now();
        let res;
        if (amILiking) {
          // 좋아요 취소
          res = http.del(`${BASE_URL}/api/posts/${postId}/likes`, null, { headers });
          let duration = Date.now() - startTime;

          metrics.unlikePost.duration.add(duration);
          const unlikeSuccess = check(res, { '상태 200': (r) => r.status === 200 });
          metrics.unlikePost.success.add(unlikeSuccess);
          metrics.unlikePost.throughput.add(1);
        } else {
          // 좋아요
          res = http.post(`${BASE_URL}/api/posts/${postId}/likes`, null, { headers });
          let duration = Date.now() - startTime;

          metrics.likePost.duration.add(duration);
          const likeSuccess = check(res, { '상태 200': (r) => r.status === 200 });
          metrics.likePost.success.add(likeSuccess);
          metrics.likePost.throughput.add(1);
        }
      }
    }
  }

  sleep(0.1);
}

// 5. 댓글 작성 벤치마크
export function testCreateComment(data) {
  const testUsers = data.testUsers;
  const userIndex = (__VU - 1) % testUsers.length;
  const user = testUsers[userIndex];

  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${user.accessToken}`,
  };

  const listRes = http.get(`${BASE_URL}/api/posts?strategy=RECENT`, { headers });
  if (listRes.status === 200) {
    const listData = JSON.parse(listRes.body);
    const posts = listData.data?.posts?.content;

    if (posts && posts.length > 0) {
      const postId = posts[Math.floor(Math.random() * posts.length)].postId;

      const payload = JSON.stringify({
        content: `벤치마크 댓글 ${Date.now()}`
      });

      const startTime = Date.now();
      const res = http.post(`${BASE_URL}/api/posts/${postId}/comments`, payload, { headers });
      const duration = Date.now() - startTime;

      metrics.createComment.duration.add(duration);
      const success = check(res, { '상태 200': (r) => r.status === 200 });
      metrics.createComment.success.add(success);
      metrics.createComment.throughput.add(1);
    }
  }

  sleep(0.2);
}

// 6. 댓글 목록 조회 벤치마크
export function testListComments(data) {
  const testUsers = data.testUsers;
  const userIndex = (__VU - 1) % testUsers.length;
  const user = testUsers[userIndex];

  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${user.accessToken}`,
  };

  const listRes = http.get(`${BASE_URL}/api/posts?strategy=RECENT`, { headers });
  if (listRes.status === 200) {
    const listData = JSON.parse(listRes.body);
    const posts = listData.data?.posts?.content;

    if (posts && posts.length > 0) {
      const postId = posts[Math.floor(Math.random() * posts.length)].postId;

      const startTime = Date.now();
      const res = http.get(`${BASE_URL}/api/posts/${postId}/comments`, { headers });
      const duration = Date.now() - startTime;

      metrics.listComments.duration.add(duration);
      const success = check(res, { '상태 200': (r) => r.status === 200 });
      metrics.listComments.success.add(success);
      metrics.listComments.throughput.add(1);
    }
  }

  sleep(0.1);
}

export function handleSummary(data) {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const filename = `performance-results/${TEST_LABEL}-${timestamp}.json`;

  console.log('\n=== 엔드포인트별 벤치마크 결과 ===\n');

  const m = data.metrics;

  console.log('📊 응답 시간 (ms) - p50 / p95 / p99:');
  console.log(`  게시글 목록: ${m.endpoint_list_posts_duration?.values?.['p(50)']?.toFixed(2)} / ${m.endpoint_list_posts_duration?.values?.['p(95)']?.toFixed(2)} / ${m.endpoint_list_posts_duration?.values?.['p(99)']?.toFixed(2)}`);
  console.log(`  게시글 상세: ${m.endpoint_get_post_detail_duration?.values?.['p(50)']?.toFixed(2)} / ${m.endpoint_get_post_detail_duration?.values?.['p(95)']?.toFixed(2)} / ${m.endpoint_get_post_detail_duration?.values?.['p(99)']?.toFixed(2)}`);
  console.log(`  게시글 작성: ${m.endpoint_create_post_duration?.values?.['p(50)']?.toFixed(2)} / ${m.endpoint_create_post_duration?.values?.['p(95)']?.toFixed(2)} / ${m.endpoint_create_post_duration?.values?.['p(99)']?.toFixed(2)}`);
  console.log(`  좋아요: ${m.endpoint_like_post_duration?.values?.['p(50)']?.toFixed(2)} / ${m.endpoint_like_post_duration?.values?.['p(95)']?.toFixed(2)} / ${m.endpoint_like_post_duration?.values?.['p(99)']?.toFixed(2)}`);
  console.log(`  좋아요 취소: ${m.endpoint_unlike_post_duration?.values?.['p(50)']?.toFixed(2)} / ${m.endpoint_unlike_post_duration?.values?.['p(95)']?.toFixed(2)} / ${m.endpoint_unlike_post_duration?.values?.['p(99)']?.toFixed(2)}`);
  console.log(`  댓글 작성: ${m.endpoint_create_comment_duration?.values?.['p(50)']?.toFixed(2)} / ${m.endpoint_create_comment_duration?.values?.['p(95)']?.toFixed(2)} / ${m.endpoint_create_comment_duration?.values?.['p(99)']?.toFixed(2)}`);
  console.log(`  댓글 목록: ${m.endpoint_list_comments_duration?.values?.['p(50)']?.toFixed(2)} / ${m.endpoint_list_comments_duration?.values?.['p(95)']?.toFixed(2)} / ${m.endpoint_list_comments_duration?.values?.['p(99)']?.toFixed(2)}`);

  console.log('\n🔥 처리량 (req/s):');
  console.log(`  게시글 목록: ${m.endpoint_list_posts_throughput?.values?.rate?.toFixed(2)}`);
  console.log(`  게시글 상세: ${m.endpoint_get_post_detail_throughput?.values?.rate?.toFixed(2)}`);
  console.log(`  게시글 작성: ${m.endpoint_create_post_throughput?.values?.rate?.toFixed(2)}`);
  console.log(`  댓글 작성: ${m.endpoint_create_comment_throughput?.values?.rate?.toFixed(2)}`);

  console.log(`\n📁 결과 저장: ${filename}`);

  return {
    [filename]: JSON.stringify(data, null, 2),
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
  };
}

export function teardown(data) {
  console.log('\n=== Step 2: 엔드포인트 벤치마크 완료 ===');
}