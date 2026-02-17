/**
 * Step 2: 병목 분석 테스트
 *
 * 목적: 특정 기능에 집중 부하를 가해 병목 지점을 찾아내기
 *
 * 실행 방법:
 *   k6 run --env BASE_URL=http://localhost:8080 --env TEST_LABEL=before test/k6-script/step2-bottleneck-analysis.js
 *
 * 전제 조건:
 *   - Step 1 (step1-seed-background.js)이 먼저 실행되어 배경 데이터가 존재해야 함
 *
 * 특징:
 *   - setup()에서 perf_tester_{i} 패턴으로 Test User 20명 생성
 *   - Access Token 배열을 return하여 테스트에서 사용
 *   - 4가지 병목 시나리오: 동시 좋아요, 대량 조회, 대량 쓰기, N+1 쿼리 감지
 */

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.1/index.js';

// 병목 분석용 메트릭
const concurrentLikeDuration = new Trend('bottleneck_concurrent_like_duration');
const concurrentLikeErrors = new Counter('bottleneck_concurrent_like_errors');
const concurrentLikeSuccess = new Rate('bottleneck_concurrent_like_success');

const heavyReadDuration = new Trend('bottleneck_heavy_read_duration');
const heavyReadSuccess = new Rate('bottleneck_heavy_read_success');

const heavyWriteDuration = new Trend('bottleneck_heavy_write_duration');
const heavyWriteSuccess = new Rate('bottleneck_heavy_write_success');

const dbConnectionErrors = new Counter('bottleneck_db_connection_errors');
const cacheHitRate = new Rate('bottleneck_cache_hit_rate');

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const TEST_LABEL = __ENV.TEST_LABEL || 'bottleneck';

const TEST_USERS_COUNT = 20;
const TEST_USER_PREFIX = 'perf_tester';
const TEST_USER_PASSWORD = 'Test1234!@#$';

// 병목 분석 시나리오 - 특정 기능에 집중 부하
export const options = {
  scenarios: {
    // 시나리오 1: 동시 좋아요 병목 테스트 (Race Condition 유발)
    concurrent_like_test: {
      executor: 'ramping-vus',
      exec: 'testConcurrentLikes',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 50 },
        { duration: '1m', target: 100 },
        { duration: '30s', target: 0 },
      ],
      startTime: '0s',
      tags: { test: 'concurrent_likes' },
    },

    // 시나리오 2: 대량 조회 부하 (캐시 효율성 테스트)
    heavy_read_test: {
      executor: 'constant-arrival-rate',
      exec: 'testHeavyRead',
      rate: 100,
      timeUnit: '1s',
      duration: '2m',
      preAllocatedVUs: 50,
      maxVUs: 100,
      startTime: '2m30s',
      tags: { test: 'heavy_read' },
    },

    // 시나리오 3: 대량 쓰기 부하 (DB 병목 테스트)
    heavy_write_test: {
      executor: 'constant-arrival-rate',
      exec: 'testHeavyWrite',
      rate: 30,
      timeUnit: '1s',
      duration: '2m',
      preAllocatedVUs: 30,
      maxVUs: 50,
      startTime: '5m',
      tags: { test: 'heavy_write' },
    },

    // 시나리오 4: N+1 쿼리 문제 감지
    nplus1_detection: {
      executor: 'ramping-vus',
      exec: 'testNPlus1Query',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 20 },
        { duration: '1m', target: 50 },
        { duration: '30s', target: 0 },
      ],
      startTime: '7m30s',
      tags: { test: 'nplus1_query' },
    },
  },
  thresholds: {
    'bottleneck_concurrent_like_duration': ['p(95)<2000', 'p(99)<4000'],
    'bottleneck_concurrent_like_errors': ['count<50'],
    'bottleneck_heavy_read_duration': ['p(95)<2000'],
    'bottleneck_heavy_write_duration': ['p(95)<3000'],
    'http_req_failed': ['rate<0.1'],
  },
};

export function setup() {
  console.log('=== Step 2: 병목 분석 테스트 시작 ===');
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
      name: `병목테스터${i}`,
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
      deviceId: `device_bottleneck_${i}_${Date.now()}`
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
  console.log('\n3. 병목 분석 시작\n');

  return {
    testUsers: testUsers,
    targetPostId: posts[0].postId,  // 모든 VU가 같은 게시글 타겟
  };
}

// 시나리오 1: 동시 좋아요 테스트 (Race Condition 병목)
export function testConcurrentLikes(data) {
  const testUsers = data.testUsers;
  const userIndex = (__VU - 1) % testUsers.length;
  const user = testUsers[userIndex];

  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${user.accessToken}`,
  };

  // 동일한 게시글에 대해 동시에 좋아요/취소 반복
  const postId = data.targetPostId;

  for (let i = 0; i < 3; i++) {
    // 현재 좋아요 상태 확인
    const detailRes = http.get(`${BASE_URL}/api/posts/${postId}`, { headers });

    if (detailRes.status === 200) {
      const detailData = JSON.parse(detailRes.body);
      const amILiking = detailData.data?.amILiking;

      const startTime = Date.now();
      let likeRes;

      if (amILiking) {
        // 좋아요 취소
        likeRes = http.del(`${BASE_URL}/api/posts/${postId}/likes`, null, { headers });
      } else {
        // 좋아요
        likeRes = http.post(`${BASE_URL}/api/posts/${postId}/likes`, null, { headers });
      }

      const duration = Date.now() - startTime;

      concurrentLikeDuration.add(duration);

      const success = check(likeRes, {
        '좋아요 액션 성공': (r) => r.status === 200,
      });

      concurrentLikeSuccess.add(success);

      if (!success) {
        concurrentLikeErrors.add(1);
      }
    }

    sleep(0.01);  // 매우 짧은 대기 (race condition 유발)
  }

  sleep(0.1);
}

// 시나리오 2: 대량 조회 테스트 (캐시 효율성)
export function testHeavyRead(data) {
  const testUsers = data.testUsers;
  const userIndex = (__VU - 1) % testUsers.length;
  const user = testUsers[userIndex];

  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${user.accessToken}`,
  };

  // 게시글 목록 조회 (캐시 효율성 확인)
  const startTime = Date.now();
  const listRes = http.get(`${BASE_URL}/api/posts?strategy=POPULAR`, { headers });
  const listDuration = Date.now() - startTime;

  heavyReadDuration.add(listDuration);
  const listSuccess = check(listRes, { '목록 조회 성공': (r) => r.status === 200 });
  heavyReadSuccess.add(listSuccess);

  if (listRes.status === 200) {
    const listData = JSON.parse(listRes.body);
    const posts = listData.data?.posts?.content;

    if (posts && posts.length > 0) {
      // 상세 조회도 수행 (캐시 히트율 측정)
      const postId = posts[0].postId;
      const detailRes = http.get(`${BASE_URL}/api/posts/${postId}`, { headers });

      // 응답 시간이 현저히 빠르면 캐시 히트로 간주
      const cacheHit = detailRes.timings.duration < 100;
      cacheHitRate.add(cacheHit);
    }
  }
}

// 시나리오 3: 대량 쓰기 테스트 (DB 커넥션 풀 병목)
export function testHeavyWrite(data) {
  const testUsers = data.testUsers;
  const userIndex = (__VU - 1) % testUsers.length;
  const user = testUsers[userIndex];

  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${user.accessToken}`,
  };

  // 게시글 작성
  const postPayload = JSON.stringify({
    title: `병목 테스트 게시글 ${Date.now()} - VU${__VU}`,
    content: 'DB 쓰기 병목 분석용 게시글입니다.',
    imageObjectKeys: []
  });

  const startTime = Date.now();
  const postRes = http.post(`${BASE_URL}/api/posts`, postPayload, { headers });
  const postDuration = Date.now() - startTime;

  heavyWriteDuration.add(postDuration);
  const postSuccess = check(postRes, { '게시글 작성 성공': (r) => r.status === 200 });
  heavyWriteSuccess.add(postSuccess);

  if (!postSuccess && postRes.status === 500) {
    dbConnectionErrors.add(1);
  }

  sleep(0.1);

  // 댓글도 작성 (추가 쓰기 부하)
  if (Math.random() < 0.5) {
    const listRes = http.get(`${BASE_URL}/api/posts?strategy=RECENT`, { headers });
    if (listRes.status === 200) {
      const listData = JSON.parse(listRes.body);
      const posts = listData.data?.posts?.content;

      if (posts && posts.length > 0) {
        const postId = posts[0].postId;
        const commentPayload = JSON.stringify({
          content: `병목 테스트 댓글 ${Date.now()}`
        });

        const commentRes = http.post(
          `${BASE_URL}/api/posts/${postId}/comments`,
          commentPayload,
          { headers }
        );

        if (commentRes.status === 500) {
          dbConnectionErrors.add(1);
        }
      }
    }
  }
}

// 시나리오 4: N+1 쿼리 문제 감지
export function testNPlus1Query(data) {
  const testUsers = data.testUsers;
  const userIndex = (__VU - 1) % testUsers.length;
  const user = testUsers[userIndex];

  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${user.accessToken}`,
  };

  // 게시글 목록 조회 (작성자 정보 포함) - N+1 쿼리 가능성
  const startTime = Date.now();
  const listRes = http.get(`${BASE_URL}/api/posts?strategy=RECENT`, { headers });
  const duration = Date.now() - startTime;

  // 10개 게시글 조회 시 응답 시간 측정
  // N+1 문제가 있으면 게시글 수에 비례하여 느려짐
  check(listRes, {
    '목록 조회 성공': (r) => r.status === 200,
    'N+1 쿼리 의심 (느림)': (r) => r.timings.duration > 1000,
  });

  if (listRes.status === 200) {
    const listData = JSON.parse(listRes.body);
    const posts = listData.data?.posts?.content;

    // 게시글 수와 응답 시간의 상관관계 확인
    if (posts) {
      const postsCount = posts.length;
      const avgTimePerPost = duration / (postsCount || 1);

      if (avgTimePerPost > 100) {
        console.warn(`N+1 쿼리 의심: ${postsCount}개 게시글에 ${duration}ms 소요 (평균 ${avgTimePerPost.toFixed(2)}ms/게시글)`);
      }
    }
  }

  sleep(0.5);
}

export function handleSummary(data) {
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const filename = `performance-results/${TEST_LABEL}-${timestamp}.json`;

  console.log('\n=== 병목 분석 결과 ===\n');

  const m = data.metrics;

  console.log('🔍 병목 지점 분석:');
  console.log(`\n1. 동시 좋아요 (Race Condition):`);
  console.log(`   - p50: ${m.bottleneck_concurrent_like_duration?.values?.['p(50)']?.toFixed(2)}ms`);
  console.log(`   - p95: ${m.bottleneck_concurrent_like_duration?.values?.['p(95)']?.toFixed(2)}ms`);
  console.log(`   - p99: ${m.bottleneck_concurrent_like_duration?.values?.['p(99)']?.toFixed(2)}ms`);
  console.log(`   - 에러 수: ${m.bottleneck_concurrent_like_errors?.values?.count || 0}개`);
  console.log(`   - 성공률: ${((m.bottleneck_concurrent_like_success?.values?.rate || 0) * 100).toFixed(2)}%`);

  console.log(`\n2. 대량 조회 (캐시 효율성):`);
  console.log(`   - p50: ${m.bottleneck_heavy_read_duration?.values?.['p(50)']?.toFixed(2)}ms`);
  console.log(`   - p95: ${m.bottleneck_heavy_read_duration?.values?.['p(95)']?.toFixed(2)}ms`);
  console.log(`   - 캐시 히트율: ${((m.bottleneck_cache_hit_rate?.values?.rate || 0) * 100).toFixed(2)}%`);

  console.log(`\n3. 대량 쓰기 (DB 병목):`);
  console.log(`   - p50: ${m.bottleneck_heavy_write_duration?.values?.['p(50)']?.toFixed(2)}ms`);
  console.log(`   - p95: ${m.bottleneck_heavy_write_duration?.values?.['p(95)']?.toFixed(2)}ms`);
  console.log(`   - p99: ${m.bottleneck_heavy_write_duration?.values?.['p(99)']?.toFixed(2)}ms`);
  console.log(`   - DB 연결 에러: ${m.bottleneck_db_connection_errors?.values?.count || 0}개`);

  console.log('\n⚠️  발견된 병목 지점:');
  const bottlenecks = [];

  if ((m.bottleneck_concurrent_like_errors?.values?.count || 0) > 10) {
    bottlenecks.push('- 동시 좋아요 처리에서 race condition 발생');
  }

  if ((m.bottleneck_heavy_read_duration?.values?.['p(95)'] || 0) > 2000) {
    bottlenecks.push('- 대량 조회 시 성능 저하 (캐시 최적화 필요)');
  }

  if ((m.bottleneck_heavy_write_duration?.values?.['p(95)'] || 0) > 3000) {
    bottlenecks.push('- 대량 쓰기 시 성능 저하 (DB 인덱스/커넥션 풀 확인 필요)');
  }

  if ((m.bottleneck_db_connection_errors?.values?.count || 0) > 0) {
    bottlenecks.push('- DB 연결 에러 발생 (커넥션 풀 크기 확인 필요)');
  }

  if ((m.bottleneck_cache_hit_rate?.values?.rate || 0) < 0.5) {
    bottlenecks.push('- 캐시 히트율 낮음 (캐시 전략 개선 필요)');
  }

  if (bottlenecks.length > 0) {
    bottlenecks.forEach(b => console.log(b));
  } else {
    console.log('- 병목 지점 없음 (양호)');
  }

  console.log(`\n📁 결과 저장: ${filename}`);

  return {
    [filename]: JSON.stringify(data, null, 2),
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
  };
}

export function teardown(data) {
  console.log('\n=== Step 2: 병목 분석 완료 ===');
  console.log('위 결과를 바탕으로 성능 개선을 진행하세요.');
}