import http from 'k6/http';
import { check, fail, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const scenario = __ENV.SCENARIO || 'smoke';
const baseUrl = (__ENV.BASE_URL || 'http://127.0.0.1:8080').replace(/\/$/, '');
const accessToken = __ENV.ACCESS_TOKEN;
const imagePath = __ENV.IMAGE_PATH;
const imageBytes = imagePath ? open(imagePath, 'b') : null;

const createPostDuration = new Trend('create_post_duration');
const imageCompletionDuration = new Trend('image_completion_duration');
const presignDuration = new Trend('presign_duration');
const uploadDuration = new Trend('image_upload_duration');
const createPostSuccess = new Rate('create_post_success');
const completionSuccess = new Rate('image_completion_success');

const optionsByScenario = {
  smoke: {
    scenarios: {
      smoke: {
        executor: 'shared-iterations',
        vus: 1,
        iterations: 1,
        maxDuration: '2m',
      },
    },
  },
  medium_10rps: {
    scenarios: {
      medium_10rps: {
        executor: 'constant-arrival-rate',
        rate: 10,
        timeUnit: '1s',
        duration: '2m',
        preAllocatedVUs: 80,
        maxVUs: 240,
      },
    },
  },
  heavy_20rps: {
    scenarios: {
      heavy_20rps: {
        executor: 'constant-arrival-rate',
        rate: 20,
        timeUnit: '1s',
        duration: '2m',
        preAllocatedVUs: 160,
        maxVUs: 480,
      },
    },
  },
  burst_5_to_30: {
    scenarios: {
      burst_5_to_30: {
        executor: 'ramping-arrival-rate',
        timeUnit: '1s',
        startRate: 5,
        preAllocatedVUs: 160,
        maxVUs: 480,
        stages: [
          { target: 5, duration: '30s' },
          { target: 30, duration: '30s' },
          { target: 30, duration: '1m' },
          { target: 5, duration: '30s' },
        ],
      },
    },
  },
};

export const options = optionsByScenario[scenario] || optionsByScenario.smoke;

function authHeaders(contentType = 'application/json') {
  return {
    Authorization: `Bearer ${accessToken}`,
    'Content-Type': contentType,
  };
}

function parseResponse(response, label) {
  try {
    return response.json();
  } catch (e) {
    fail(`${label}: failed to parse json: ${e}`);
  }
}

function loadImageBytes() {
  if (!imagePath || !imageBytes) {
    fail('IMAGE_PATH is required');
  }
  return imageBytes;
}

function waitForCompletion(postId, startedAt) {
  const deadline = Date.now() + 120000;
  while (Date.now() < deadline) {
    const detailRes = http.get(`${baseUrl}/api/posts/${postId}`, {
      headers: authHeaders(),
      timeout: '10s',
    });

    if (detailRes.status !== 200) {
      sleep(1);
      continue;
    }

    const payload = parseResponse(detailRes, 'post detail');
    const imageStatus = payload?.data?.imageStatus;

    if (imageStatus === 'COMPLETED') {
      imageCompletionDuration.add(Date.now() - startedAt);
      completionSuccess.add(true);
      return;
    }

    if (imageStatus === 'FAILED') {
      completionSuccess.add(false);
      fail(`image processing failed for postId=${postId}`);
    }

    sleep(1);
  }

  completionSuccess.add(false);
  fail(`image processing timeout for postId=${postId}`);
}

export default function () {
  if (!accessToken) {
    fail('ACCESS_TOKEN is required');
  }

  const bytes = loadImageBytes();
  const filename = `k6-v2-${__VU}-${__ITER}.png`;

  const presignRes = http.post(
    `${baseUrl}/api/posts/images/presigned-url`,
    JSON.stringify({
      files: [
        {
          fileName: filename,
          mimeType: 'image/png',
        },
      ],
    }),
    { headers: authHeaders() },
  );
  presignDuration.add(presignRes.timings.duration);
  check(presignRes, {
    'presign status 200': (r) => r.status === 200,
  }) || fail(`presign failed: ${presignRes.status} ${presignRes.body}`);

  const presignPayload = parseResponse(presignRes, 'presign');
  const presignUrl = presignPayload.data.urls[0].presignedUrl;
  const objectKey = presignPayload.data.urls[0].objectKey;

  const uploadRes = http.put(presignUrl, bytes, {
    headers: {
      'Content-Type': 'image/png',
    },
  });
  uploadDuration.add(uploadRes.timings.duration);
  check(uploadRes, {
    'upload status 200 or 204': (r) => r.status === 200 || r.status === 204,
  }) || fail(`upload failed: ${uploadRes.status} ${uploadRes.body}`);

  const startedAt = Date.now();
  const createRes = http.post(
    `${baseUrl}/api/posts`,
    JSON.stringify({
      title: `experiment post ${__VU}-${__ITER}`,
      content: `scenario=${scenario}, vu=${__VU}, iter=${__ITER}`,
      imageObjectKeys: [objectKey],
    }),
    { headers: authHeaders() },
  );

  createPostDuration.add(createRes.timings.duration);
  const ok = check(createRes, {
    'create post status 200': (r) => r.status === 200,
  });
  createPostSuccess.add(ok);

  if (!ok) {
    fail(`create post failed: ${createRes.status} ${createRes.body}`);
  }

  const payload = parseResponse(createRes, 'create post');
  const postId = payload?.data?.postId;
  if (!postId) {
    fail(`postId missing in create response: ${createRes.body}`);
  }

  waitForCompletion(postId, startedAt);
}
