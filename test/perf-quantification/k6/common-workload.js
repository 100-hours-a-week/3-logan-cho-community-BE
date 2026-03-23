import http from 'k6/http';

export const DEFAULT_PASSWORD = __ENV.TEST_PASSWORD || 'Test1234!@#$';

export function parseJson(resp) {
  try {
    return JSON.parse(resp.body);
  } catch (err) {
    return null;
  }
}

export function extractAccessToken(data) {
  if (!data) return null;

  if (typeof data.data?.accessJwt === 'string') return data.data.accessJwt;
  if (typeof data.data?.accessToken === 'string') return data.data.accessToken;
  if (typeof data.accessJwt === 'string') return data.accessJwt;
  if (typeof data.accessToken === 'string') return data.accessToken;
  if (typeof data.token === 'string') return data.token;

  return null;
}

export function ensureUser(baseUrl, idx, sharedUserPrefix) {
  const email = `${sharedUserPrefix}-${idx}@example.com`;
  const signupPayload = JSON.stringify({
    email,
    password: DEFAULT_PASSWORD,
    name: `perf-${idx}`,
    imageObjectKey: null,
    emailVerifiedToken: 'dummy',
  });

  http.post(`${baseUrl}/api/members`, signupPayload, {
    headers: { 'Content-Type': 'application/json' },
  });

  const loginPayload = JSON.stringify({
    email,
    password: DEFAULT_PASSWORD,
    deviceId: `${sharedUserPrefix}-device-${idx}-${Date.now()}`,
  });

  const login = http.post(`${baseUrl}/api/auth`, loginPayload, {
    headers: { 'Content-Type': 'application/json' },
  });
  const body = parseJson(login);
  const token = extractAccessToken(body);

  return { email, token };
}

export function randomToken(users) {
  if (!users || users.length === 0) return null;
  const idx = Math.floor(Math.random() * users.length);
  return users[idx].token;
}

export function makeAuthHeader(token) {
  return token ? { Authorization: `Bearer ${token}` } : {};
}

export function extractPosts(body) {
  if (!body || !body.data) return [];
  if (Array.isArray(body.data.posts?.items)) return body.data.posts.items;
  if (Array.isArray(body.data?.items)) return body.data.items;
  return [];
}
