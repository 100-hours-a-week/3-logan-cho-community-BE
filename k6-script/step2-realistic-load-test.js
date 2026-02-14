import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// 커스텀 메트릭
const listPostsSuccess = new Rate('list_posts_success');
const getPostDetailSuccess = new Rate('get_post_detail_success');
const createPostSuccess = new Rate('create_post_success');
const createCommentSuccess = new Rate('create_comment_success');
const likeActionSuccess = new Rate('like_action_success');
const loginFailures = new Counter('login_failures');

// 환경 변수
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const TEST_LABEL = __ENV.TEST_LABEL || 'realistic-load';

// 테스트 사용자 설정
const TEST_USERS_COUNT = 30;
const TEST_USER_PREFIX = 'perf_tester';
const TEST_USER_PASSWORD = 'Test1234!@#$';

// 부하 테스트 시나리오 설정
export const options = {
  scenarios: {
    // 일반 사용자 부하 테스트
    normal_user_load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 10 },   // 30초간 10명으로 증가 (워밍업)
        { duration: '2m', target: 30 },    // 2분간 30명으로 증가
        { duration: '3m', target: 30 },    // 3분간 30명 유지 (안정 부하)
        { duration: '2m', target: 50 },    // 2분간 50명으로 증가
        { duration: '3m', target: 50 },    // 3분간 50명 유지 (고부하)
        { duration: '1m', target: 100 },   // 1분간 100명으로 증가 (피크)
        { duration: '2m', target: 100 },   // 2분간 100명 유지
        { duration: '1m', target: 0 },     // 1분간 0으로 감소 (쿨다운)
      ],
      gracefulStop: '30s',
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<3000', 'p(99)<5000'], // 95%는 3초 이내, 99%는 5초 이내
    http_req_failed: ['rate<0.05'],                  // 실패율 5% 미만
    list_posts_success: ['rate>0.95'],               // 목록 조회 성공률 95% 이상
    get_post_detail_success: ['rate>0.95'],          // 상세 조회 성공률 95% 이상
    create_post_success: ['rate>0.90'],              // 게시글 작성 성공률 90% 이상
    create_comment_success: ['rate>0.90'],           // 댓글 작성 성공률 90% 이상
    login_failures: ['count<10'],                    // 로그인 실패 10회 미만
  },
};

// Setup: 테스트 사용자 생성 및 로그인
export function setup() {
  console.log('=== Step 2: 일반 사용자 부하 테스트 시작 ===');
  console.log(`대상 서버: ${BASE_URL}`);
  console.log(`테스트 레이블: ${TEST_LABEL}`);

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
      name: `부하테스터${i}`,
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
      deviceId: `device_realistic_${i}_${Date.now()}`
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

    sleep(0.05);  // API 부하 방지
  }

  console.log(`✓ 테스트 사용자 준비 완료: ${testUsers.length}명`);
  console.log('\n3. 부하 테스트 시작\n');

  return {
    testUsers: testUsers,
    initialPostCount: posts.length,
  };
}

// 메인 테스트 시나리오
export default function(data) {
  const testUsers = data.testUsers;

  if (!testUsers || testUsers.length === 0) {
    console.error('테스트 사용자가 없습니다.');
    loginFailures.add(1);
    sleep(1);
    return;
  }

  // VU에 따라 테스트 사용자 할당
  const userIndex = (__VU - 1) % testUsers.length;
  const user = testUsers[userIndex];

  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${user.accessToken}`,
  };

  // 일반 사용자 행동 패턴 시뮬레이션
  const action = Math.random();

  if (action < 0.50) {
    // 50%: 게시글 목록 조회 (가장 흔한 행동)
    group('게시글 목록 조회', () => {
      const strategy = Math.random() < 0.7 ? 'RECENT' : 'POPULAR';
      const listRes = http.get(
        `${BASE_URL}/api/posts?strategy=${strategy}`,
        { headers }
      );

      const success = check(listRes, {
        '상태 코드 200': (r) => r.status === 200,
        '응답 시간 < 2초': (r) => r.timings.duration < 2000,
      });

      listPostsSuccess.add(success);
    });

    sleep(Math.random() * 2 + 1); // 1-3초 대기

  } else if (action < 0.75) {
    // 25%: 게시글 상세 조회
    group('게시글 상세 조회', () => {
      // 먼저 목록에서 게시글 ID 가져오기
      const listRes = http.get(
        `${BASE_URL}/api/posts?strategy=RECENT`,
        { headers }
      );

      if (listRes.status === 200) {
        const listData = JSON.parse(listRes.body);
        const posts = listData.data?.posts?.content;

        if (posts && posts.length > 0) {
          // 랜덤하게 게시글 선택
          const randomPost = posts[Math.floor(Math.random() * posts.length)];
          const postId = randomPost.postId;

          // 상세 조회
          const detailRes = http.get(
            `${BASE_URL}/api/posts/${postId}`,
            { headers }
          );

          const success = check(detailRes, {
            '상태 코드 200': (r) => r.status === 200,
            '응답 시간 < 2초': (r) => r.timings.duration < 2000,
          });

          getPostDetailSuccess.add(success);

          // 상세 페이지에서 댓글도 조회 (50% 확률)
          if (Math.random() < 0.5) {
            sleep(0.5);
            const commentsRes = http.get(
              `${BASE_URL}/api/posts/${postId}/comments`,
              { headers }
            );

            check(commentsRes, {
              '댓글 조회 성공': (r) => r.status === 200,
            });
          }
        }
      }
    });

    sleep(Math.random() * 3 + 2); // 2-5초 대기 (읽는 시간)

  } else if (action < 0.85) {
    // 10%: 게시글 작성
    group('게시글 작성', () => {
      const titles = [
        '오늘의 일상',
        '맛집 추천',
        '여행 후기',
        '질문있어요',
        '정보 공유',
        '후기 남깁니다',
        '도움 요청',
        '의견 궁금해요',
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
        title: `${randomTitle} - VU${__VU} - ${Date.now()}`,
        content: randomContent,
        imageObjectKeys: []
      });

      const createRes = http.post(
        `${BASE_URL}/api/posts`,
        postPayload,
        { headers }
      );

      const success = check(createRes, {
        '상태 코드 200': (r) => r.status === 200,
        '응답 시간 < 3초': (r) => r.timings.duration < 3000,
      });

      createPostSuccess.add(success);
    });

    sleep(Math.random() * 2 + 1); // 1-3초 대기

  } else if (action < 0.95) {
    // 10%: 댓글 작성
    group('댓글 작성', () => {
      // 목록에서 게시글 선택
      const listRes = http.get(
        `${BASE_URL}/api/posts?strategy=RECENT`,
        { headers }
      );

      if (listRes.status === 200) {
        const listData = JSON.parse(listRes.body);
        const posts = listData.data?.posts?.content;

        if (posts && posts.length > 0) {
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

          const commentRes = http.post(
            `${BASE_URL}/api/posts/${postId}/comments`,
            commentPayload,
            { headers }
          );

          const success = check(commentRes, {
            '상태 코드 200': (r) => r.status === 200,
            '응답 시간 < 2초': (r) => r.timings.duration < 2000,
          });

          createCommentSuccess.add(success);
        }
      }
    });

    sleep(Math.random() * 2 + 1); // 1-3초 대기

  } else {
    // 5%: 좋아요 또는 좋아요 취소 (amILiking 확인 후 처리)
    group('좋아요 액션', () => {
      const listRes = http.get(
        `${BASE_URL}/api/posts?strategy=POPULAR`,
        { headers }
      );

      if (listRes.status === 200) {
        const listData = JSON.parse(listRes.body);
        const posts = listData.data?.posts?.content;

        if (posts && posts.length > 0) {
          const randomPost = posts[Math.floor(Math.random() * posts.length)];
          const postId = randomPost.postId;

          // 현재 좋아요 상태 확인
          const detailRes = http.get(`${BASE_URL}/api/posts/${postId}`, { headers });

          if (detailRes.status === 200) {
            const detailData = JSON.parse(detailRes.body);
            const amILiking = detailData.data?.amILiking;

            let likeRes;
            if (amILiking) {
              // 좋아요 취소
              likeRes = http.del(`${BASE_URL}/api/posts/${postId}/likes`, null, { headers });
            } else {
              // 좋아요
              likeRes = http.post(`${BASE_URL}/api/posts/${postId}/likes`, null, { headers });
            }

            const success = check(likeRes, { '상태 200': (r) => r.status === 200 });
            likeActionSuccess.add(success);
          }
        }
      }
    });

    sleep(Math.random() * 1 + 0.5); // 0.5-1.5초 대기
  }
}

// Teardown
export function teardown(data) {
  console.log('\n=== Step 2: 부하 테스트 완료 ===');
  console.log('개선 후에는 동일한 테스트를 다시 실행하여 비교하세요.');
}