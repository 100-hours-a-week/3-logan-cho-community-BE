/**
 * Step 1: 배경 데이터 생성 (Background Data Seeding)
 *
 * 목적: DB에 초기 데이터를 채워 넣어 "Not Empty" 상태로 만들기
 *
 * 실행 방법 (Docker Compose):
 *   export BASE_URL=http://3.39.234.82:8080  # 테스트 대상 서버 주소
 *   docker compose run --rm k6 run --env BASE_URL=$BASE_URL /scripts/step1-seed-background.js
 *
 * 특징:
 *   - dummy_user_{i} 패턴으로 Mock User 50명 생성
 *   - 게시글 150개, 댓글 ~450개, 좋아요 ~750개 생성
 *   - exec.scenario.iterationInTest 사용으로 중복 없는 고유 ID 보장
 *   - 성능 메트릭 수집 없음 (데이터 생성에만 집중)
 *   - 병렬 처리로 빠르게 실행
 */

import http from 'k6/http';
import { sleep } from 'k6';
import exec from 'k6/execution';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// 배경 데이터 설정
const DUMMY_USERS_COUNT = 50;
const DUMMY_USER_PREFIX = 'dummy_user';
const DUMMY_USER_PASSWORD = 'Test1234!@#$';

const TARGET_POSTS_COUNT = 500;  // 게시글 150개 생성
const COMMENTS_PER_POST = 3;     // 게시글당 평균 댓글 3개
const LIKES_PER_POST = 5;        // 게시글당 평균 좋아요 5개

// K6 설정 - 빠른 병렬 처리
export const options = {
  scenarios: {
    // 시나리오 1: 사용자 생성
    create_users: {
      executor: 'shared-iterations',
      exec: 'createUsers',
      vus: 50,
      iterations: DUMMY_USERS_COUNT,
      maxDuration: '2m',
      tags: { phase: 'user_creation' },
    },
    // 시나리오 2: 게시글 생성
    create_posts: {
      executor: 'shared-iterations',
      exec: 'createPosts',
      vus: 50,
      iterations: TARGET_POSTS_COUNT,
      maxDuration: '3m',
      startTime: '2m',  // 사용자 생성 후 시작
      tags: { phase: 'post_creation' },
    },
    // 시나리오 3: 댓글 생성
    create_comments: {
      executor: 'shared-iterations',
      exec: 'createComments',
      vus: 50,
      iterations: TARGET_POSTS_COUNT * COMMENTS_PER_POST,
      maxDuration: '3m',
      startTime: '4m',  // 게시글 생성 후 시작
      tags: { phase: 'comment_creation' },
    },
    // 시나리오 4: 좋아요 생성
    create_likes: {
      executor: 'shared-iterations',
      exec: 'createLikes',
      vus: 50,
      iterations: TARGET_POSTS_COUNT * LIKES_PER_POST,
      maxDuration: '2m',
      startTime: '7m',  // 댓글 생성 후 시작
      tags: { phase: 'like_creation' },
    },
  },
  thresholds: {
    // 메트릭 수집 안함 (데이터 생성에만 집중)
  },
};

// Setup: 공유 데이터 준비
export function setup() {
  console.log('=== Step 1: 배경 데이터 생성 시작 ===');
  console.log(`대상 서버: ${BASE_URL}`);
  console.log(`생성할 사용자: ${DUMMY_USERS_COUNT}명`);
  console.log(`생성할 게시글: ${TARGET_POSTS_COUNT}개`);
  console.log(`생성할 댓글: 약 ${TARGET_POSTS_COUNT * COMMENTS_PER_POST}개`);
  console.log(`생성할 좋아요: 약 ${TARGET_POSTS_COUNT * LIKES_PER_POST}개\n`);

  // 테스트 사용자 1명을 생성하고 로그인하여 인증 플로우 검증
  console.log('0. 인증 플로우 사전 검증 중...');
  const testEmail = `${DUMMY_USER_PREFIX}_test_validation@test.com`;

  const testSignupPayload = JSON.stringify({
    email: testEmail,
    password: DUMMY_USER_PASSWORD,
    name: '검증용유저',
    imageObjectKey: null,
    emailVerifiedToken: 'dummy_token'
  });

  const testSignupRes = http.post(
    `${BASE_URL}/api/members`,
    testSignupPayload,
    { headers: { 'Content-Type': 'application/json' } }
  );

  console.log(`  회원가입 테스트: status=${testSignupRes.status}`);
  if (testSignupRes.status !== 200 && testSignupRes.status !== 400) {
    console.error(`  회원가입 실패: ${testSignupRes.body}`);
    throw new Error(`회원가입 API 오류: ${testSignupRes.status}`);
  }

  // 로그인 테스트
  sleep(0.1);
  const testLoginPayload = JSON.stringify({
    email: testEmail,
    password: DUMMY_USER_PASSWORD,
    deviceId: `device_validation_${Date.now()}`
  });

  const testLoginRes = http.post(
    `${BASE_URL}/api/auth`,
    testLoginPayload,
    { headers: { 'Content-Type': 'application/json' } }
  );

  console.log(`  로그인 테스트: status=${testLoginRes.status}`);

  if (testLoginRes.status !== 200) {
    console.error(`  ✗ 로그인 실패! status=${testLoginRes.status}, body=${testLoginRes.body}`);
    console.error(`  원인 분석:`);
    console.error(`    - 회원가입은 성공했지만 로그인이 실패합니다.`);
    console.error(`    - 이메일 인증이 필요한지 확인하세요.`);
    console.error(`    - SecurityConfig.java 설정을 확인하세요.`);
    console.error(`    - 백엔드 로그에서 실제 오류 원인을 확인하세요.`);
    throw new Error('인증 플로우 검증 실패: 회원가입 후 로그인 불가');
  }

  const testLoginData = JSON.parse(testLoginRes.body);
  const testAccessToken = testLoginData.data?.accessJwt;  // 필드명: accessJwt

  if (!testAccessToken) {
    console.error(`  ✗ 액세스 토큰 없음! body=${testLoginRes.body}`);
    throw new Error('인증 플로우 검증 실패: 토큰 발급 불가');
  }

  console.log(`  ✓ 인증 플로우 검증 성공! (회원가입 → 로그인 → 토큰 발급)\n`);

  return {
    userCount: DUMMY_USERS_COUNT,
    postCount: TARGET_POSTS_COUNT,
  };
}

// 시나리오 1: 사용자 생성
export function createUsers() {
  // exec.scenario.iterationInTest: 전체 테스트에서의 글로벌 iteration 번호 (중복 없음)
  const userIndex = exec.scenario.iterationInTest;
  const email = `${DUMMY_USER_PREFIX}_${userIndex}@test.com`;

  const signupPayload = JSON.stringify({
    email: email,
    password: DUMMY_USER_PASSWORD,
    name: `더미유저${userIndex}`,
    imageObjectKey: null,
    emailVerifiedToken: 'dummy_token'
  });

  const signupRes = http.post(
    `${BASE_URL}/api/members`,
    signupPayload,
    { headers: { 'Content-Type': 'application/json' } }
  );

  if (signupRes.status === 200) {
    if (userIndex % 10 === 0) {
      console.log(`✓ ${userIndex + 1}명 사용자 생성 완료`);
    }
  } else if (signupRes.status === 400) {
    // 400 에러의 원인을 상세히 로그 (이메일 중복 vs 다른 문제)
    console.warn(`⚠ 사용자 ${userIndex} 생성 400 에러: ${signupRes.body}`);
  } else {
    // 다른 오류의 경우 로그 출력
    console.error(`✗ 사용자 ${userIndex} 생성 실패: ${signupRes.status} - ${signupRes.body}`);
  }

  sleep(0.05);
}

// 시나리오 2: 게시글 생성
export function createPosts() {
  // exec.scenario.iterationInTest: 전체 테스트에서의 글로벌 iteration 번호
  const postIndex = exec.scenario.iterationInTest;

  // 무작위 사용자 선택
  const userIndex = Math.floor(Math.random() * DUMMY_USERS_COUNT);
  const user = loginUser(userIndex);

  if (!user) {
    console.error(`✗ 사용자 ${userIndex} 로그인 실패`);
    return;
  }

  const titles = [
    '오늘의 일상',
    '맛집 추천',
    '여행 후기',
    '질문 있어요',
    '정보 공유',
    '후기 남깁니다',
    '도움 필요',
    '의견 궁금',
    '제 이야기',
    '추천 부탁'
  ];

  const contents = [
    '오늘 정말 좋은 하루였습니다.',
    '이 장소 추천합니다.',
    '다녀온 여행 공유합니다.',
    '궁금한 점이 있어요.',
    '유용한 정보 공유합니다.',
    '경험담 들려드릴게요.',
    '이 부분 도움 필요해요.',
    '여러분 의견이 궁금합니다.',
    '제 생각을 말씀드릴게요.',
    '좋은 추천 부탁드립니다.'
  ];

  const randomTitle = titles[Math.floor(Math.random() * titles.length)];
  const randomContent = contents[Math.floor(Math.random() * contents.length)];

  const postPayload = JSON.stringify({
    title: `${randomTitle} ${postIndex + 1}`,
    content: randomContent,
    imageObjectKeys: []
  });

  const postRes = http.post(
    `${BASE_URL}/api/posts`,
    postPayload,
    {
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${user.accessToken}`,
      }
    }
  );

  if (postRes.status === 200) {
    if (postIndex % 20 === 0) {
      console.log(`✓ ${postIndex + 1}개 게시글 생성 완료`);
    }
  } else {
    console.error(`✗ 게시글 ${postIndex} 생성 실패: ${postRes.status}`);
  }

  sleep(0.05);
}

// 시나리오 3: 댓글 생성
export function createComments() {
  // 무작위 사용자 선택
  const userIndex = Math.floor(Math.random() * DUMMY_USERS_COUNT);
  const user = loginUser(userIndex);

  if (!user) {
    return;
  }

  // 게시글 목록 가져오기
  const listRes = http.get(
    `${BASE_URL}/api/posts?strategy=RECENT`,
    {
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${user.accessToken}`,
      }
    }
  );

  if (listRes.status !== 200) {
    return;
  }

  const listData = JSON.parse(listRes.body);
  const posts = listData.data?.posts?.content;

  if (!posts || posts.length === 0) {
    return;
  }

  // 무작위 게시글 선택
  const randomPost = posts[Math.floor(Math.random() * posts.length)];
  const postId = randomPost.postId;

  const comments = [
    '좋은 글 감사합니다!',
    '동감합니다.',
    '유익한 정보네요.',
    '공감해요.',
    '도움되었습니다.',
    '멋지네요!',
    '잘 보고 갑니다.',
    '응원합니다!',
    '저도 그렇게 생각해요.',
    '좋은 하루 되세요~'
  ];

  const randomComment = comments[Math.floor(Math.random() * comments.length)];

  const commentPayload = JSON.stringify({
    content: randomComment
  });

  http.post(
    `${BASE_URL}/api/posts/${postId}/comments`,
    commentPayload,
    {
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${user.accessToken}`,
      }
    }
  );

  sleep(0.05);
}

// 시나리오 4: 좋아요 생성
export function createLikes() {
  // 무작위 사용자 선택
  const userIndex = Math.floor(Math.random() * DUMMY_USERS_COUNT);
  const user = loginUser(userIndex);

  if (!user) {
    return;
  }

  // 게시글 목록 가져오기
  const listRes = http.get(
    `${BASE_URL}/api/posts?strategy=POPULAR`,
    {
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${user.accessToken}`,
      }
    }
  );

  if (listRes.status !== 200) {
    return;
  }

  const listData = JSON.parse(listRes.body);
  const posts = listData.data?.posts?.content;

  if (!posts || posts.length === 0) {
    return;
  }

  // 무작위 게시글 선택
  const randomPost = posts[Math.floor(Math.random() * posts.length)];
  const postId = randomPost.postId;

  // 좋아요 (이미 좋아요한 경우 실패해도 무시)
  http.post(
    `${BASE_URL}/api/posts/${postId}/likes`,
    null,
    {
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${user.accessToken}`,
      }
    }
  );

  sleep(0.05);
}

// Helper: 사용자 로그인
function loginUser(userIndex) {
  const email = `${DUMMY_USER_PREFIX}_${userIndex}@test.com`;
  const password = DUMMY_USER_PASSWORD;

  const loginPayload = JSON.stringify({
    email: email,
    password: password,
    deviceId: `device_dummy_${userIndex}_${Date.now()}`
  });

  const loginRes = http.post(
    `${BASE_URL}/api/auth`,
    loginPayload,
    { headers: { 'Content-Type': 'application/json' } }
  );

  if (loginRes.status !== 200) {
    // 로그인 실패 원인 상세 로그 (처음 3번만 출력하여 로그 스팸 방지)
    if (userIndex < 3) {
      console.error(`✗ 로그인 실패 [user ${userIndex}, ${email}]: status=${loginRes.status}, body=${loginRes.body}`);
    }
    return null;
  }

  const loginData = JSON.parse(loginRes.body);
  const accessToken = loginData.data?.accessJwt;  // 필드명: accessJwt

  if (!accessToken) {
    if (userIndex < 3) {
      console.error(`✗ 토큰 없음 [user ${userIndex}, ${email}]: body=${loginRes.body}`);
    }
    return null;
  }

  return { email, accessToken };
}

// Teardown
export function teardown(data) {
  console.log('\n=== Step 1: 배경 데이터 생성 완료 ===');
  console.log('이제 Step 2 테스트를 실행할 수 있습니다.');
}