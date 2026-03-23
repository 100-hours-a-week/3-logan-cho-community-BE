import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend } from 'k6/metrics';
import { parseJson, ensureUser, randomToken, makeAuthHeader, extractPosts } from './common-workload.js';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const WORKLOAD = __ENV.WORKLOAD || 'list_detail';
const USERS = Number(__ENV.USERS || 20);
const USER_PREFIX = __ENV.AUTH_EMAIL_PREFIX || 'perf-user';
const VUS = Number(__ENV.VUS || 20);
const DURATION = __ENV.DURATION || '3m';
const POST_ID = __ENV.POST_ID || '';
const FIXED_POST_ID = POST_ID;
const LIST_USE_PIPELINE = (__ENV.LIST_USE_PIPELINE || 'true').toLowerCase() === 'true';
const LIST_USE_PIPELINE_PARAM = `usePipeline=${LIST_USE_PIPELINE ? 'true' : 'false'}`;

export const options = {
  scenarios: {
    main: {
      executor: 'constant-vus',
      vus: VUS,
      duration: DURATION,
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.02'],
    http_req_duration: ['p(95)<5000'],
    http_req_connecting: ['p(95)<500'],
  },
};

const listTrend = new Trend('list_list_duration');
const detailTrend = new Trend('detail_duration');

let userStore = [];
let samplePostIds = [];

export function setup() {
  const users = [];

  for (let i = 0; i < USERS; i += 1) {
    const user = ensureUser(BASE_URL, i, USER_PREFIX);
    if (user.token) users.push(user);
  }

  if (users.length === 0) {
    throw new Error('유효한 테스트 사용자 토큰이 없습니다.');
  }

  const token = randomToken(users);
  const list = http.get(`${BASE_URL}/api/posts`, { headers: makeAuthHeader(token) });
  const payload = parseJson(list);
  const posts = extractPosts(payload);

  if (posts && posts.length > 0) {
    samplePostIds = posts.map((p) => p.postId || p._id || '');
  }

  return { users, samplePostIds };
}

export default function (data) {
  const users = data.users;
  const posts = data.samplePostIds || samplePostIds;
  const token = randomToken(users);
  const headers = makeAuthHeader(token);

  const headersBase = {
    headers: {
      'Content-Type': 'application/json',
      ...headers,
    },
  };

  if (WORKLOAD === 'list_profile') {
    const r1 = http.get(`${BASE_URL}/api/posts?${LIST_USE_PIPELINE_PARAM}`, headersBase);
    listTrend.add(r1.timings.duration);
    check(r1, {
      list_ok: (r) => r.status === 200,
    });
    sleep(1);
    return;
  }

  if (WORKLOAD === 'view_burst' && posts.length > 0) {
    const target = FIXED_POST_ID || posts[0];
    const detailUrl = `${BASE_URL}/api/posts/${target}`;
    const r2 = http.get(detailUrl, headersBase);
    detailTrend.add(r2.timings.duration);
    check(r2, {
      detail_ok: (r) => r.status === 200,
    });
    sleep(0.5);
    return;
  }

  if (WORKLOAD === 'list_detail') {
    const r1 = http.get(`${BASE_URL}/api/posts?${LIST_USE_PIPELINE_PARAM}`, headersBase);
    listTrend.add(r1.timings.duration);
    const p1 = parseJson(r1);
    const list = extractPosts(p1);

    if (Array.isArray(list) && list.length > 0) {
      const post = list[Math.floor(Math.random() * list.length)];
      const postId = post?.postId || post?._id;
      if (postId) {
        const r2 = http.get(`${BASE_URL}/api/posts/${postId}`, headersBase);
        detailTrend.add(r2.timings.duration);
        check(r2, {
          detail_ok: (r) => r.status === 200,
        });
      }
    }
    sleep(1);
    return;
  }

  throw new Error(`지원하지 않는 WORKLOAD: ${WORKLOAD}`);
}

export function handleSummary(data) {
  return {
    stdout: JSON.stringify({
      metrics: Object.keys(data.metrics),
      stats: {
        list_p95: data.metrics?.list_list_duration?.values?.['p(95)'],
        detail_p95: data.metrics?.detail_duration?.values?.['p(95)'],
        failed_rate: data.metrics?.http_req_failed?.values?.rate,
      },
      options: {
        workload: WORKLOAD,
        base: BASE_URL,
      },
    }, null, 2),
  };
}
