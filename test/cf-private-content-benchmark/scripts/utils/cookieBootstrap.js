'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { URL } = require('node:url');

const { runCurl } = require('./curlRunner');

function resolveBootstrapPayload(entry) {
  if (!entry.bootstrap || !entry.bootstrap.url) {
    throw new Error(`Missing bootstrap.url for cookie entry "${entry.label}"`);
  }

  const payload = {
    targetUrl: entry.url
  };

  if (entry.bootstrap.resourcePath) {
    payload.resourcePath = entry.bootstrap.resourcePath;
  }

  if (entry.bootstrap.resourceUrl) {
    payload.resourceUrl = entry.bootstrap.resourceUrl;
  }

  if (entry.bootstrap.resourcePattern) {
    payload.resourcePattern = entry.bootstrap.resourcePattern;
  }

  if (entry.bootstrap.cookieDomain) {
    payload.cookieDomain = entry.bootstrap.cookieDomain;
  }

  if (entry.bootstrap.ttlSeconds) {
    payload.ttlSeconds = entry.bootstrap.ttlSeconds;
  }

  if (entry.bootstrap.cookiePath) {
    payload.cookiePath = entry.bootstrap.cookiePath;
  }

  return payload;
}

function makeTempFile(prefix, extension) {
  const randomPart = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  return path.join(os.tmpdir(), `${prefix}-${randomPart}${extension}`);
}

function writeCookieJar({ cookieFilePath, targetUrl, cookies, expiresAt, cookiePath }) {
  const parsedUrl = new URL(targetUrl);
  const domain = parsedUrl.hostname;
  const secure = parsedUrl.protocol === 'https:' ? 'TRUE' : 'FALSE';
  const expiryEpoch = Math.floor(new Date(expiresAt).getTime() / 1000);
  const jarLines = [
    '# Netscape HTTP Cookie File'
  ];

  for (const [name, value] of Object.entries(cookies)) {
    jarLines.push([
      domain,
      'FALSE',
      cookiePath || '/',
      secure,
      expiryEpoch,
      name,
      value
    ].join('\t'));
  }

  fs.writeFileSync(cookieFilePath, `${jarLines.join('\n')}\n`, 'utf8');
}

async function issueBootstrapCookie(entry) {
  const outputFile = makeTempFile('cf-bootstrap-response', '.json');
  const payload = resolveBootstrapPayload(entry);
  const metrics = await runCurl({
    url: entry.bootstrap.url,
    method: 'POST',
    headers: ['Content-Type: application/json'],
    body: JSON.stringify(payload),
    outputFile
  });

  const bodyText = fs.readFileSync(outputFile, 'utf8').trim();
  fs.unlinkSync(outputFile);

  let responseBody = {};
  if (bodyText) {
    responseBody = JSON.parse(bodyText);
  }

  if (!responseBody.cookies || typeof responseBody.cookies !== 'object') {
    throw new Error(`Bootstrap server did not return cookies for "${entry.label}"`);
  }

  const cookieFilePath = makeTempFile('cf-signed-cookie', '.txt');
  writeCookieJar({
    cookieFilePath,
    targetUrl: entry.url,
    cookies: responseBody.cookies,
    expiresAt: responseBody.expiresAt || new Date(Date.now() + 5 * 60 * 1000).toISOString(),
    cookiePath: responseBody.cookiePath || entry.bootstrap.cookiePath || '/'
  });

  return {
    metrics,
    cookieFilePath,
    bootstrapLabel: entry.bootstrap.label || entry.bootstrap.url,
    responseBody
  };
}

function cleanupCookieFile(cookieFilePath) {
  if (!cookieFilePath) {
    return;
  }

  try {
    fs.unlinkSync(cookieFilePath);
  } catch (error) {
    if (error.code !== 'ENOENT') {
      throw error;
    }
  }
}

module.exports = {
  issueBootstrapCookie,
  cleanupCookieFile
};
