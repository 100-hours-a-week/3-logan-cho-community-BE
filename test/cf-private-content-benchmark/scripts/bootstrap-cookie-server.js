#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const http = require('node:http');
const { URL } = require('node:url');
const crypto = require('node:crypto');

function parseArgs(argv) {
  const parsed = {
    host: '127.0.0.1',
    port: 3100,
    distributionDomain: '',
    keyPairId: '',
    privateKeyFile: '',
    privateKeyBase64: '',
    defaultTtlSeconds: 300,
    cookiePath: '/',
    cookieDomain: ''
  };

  for (let index = 2; index < argv.length; index += 1) {
    const token = argv[index];
    const next = argv[index + 1];

    if (token === '--host' && next) {
      parsed.host = next;
      index += 1;
      continue;
    }

    if (token === '--port' && next) {
      parsed.port = Number(next);
      index += 1;
      continue;
    }

    if (token === '--distribution-domain' && next) {
      parsed.distributionDomain = next;
      index += 1;
      continue;
    }

    if (token === '--key-pair-id' && next) {
      parsed.keyPairId = next;
      index += 1;
      continue;
    }

    if (token === '--private-key-file' && next) {
      parsed.privateKeyFile = next;
      index += 1;
      continue;
    }

    if (token === '--private-key-base64' && next) {
      parsed.privateKeyBase64 = next;
      index += 1;
      continue;
    }

    if (token === '--default-ttl-seconds' && next) {
      parsed.defaultTtlSeconds = Number(next);
      index += 1;
      continue;
    }

    if (token === '--cookie-path' && next) {
      parsed.cookiePath = next;
      index += 1;
      continue;
    }

    if (token === '--cookie-domain' && next) {
      parsed.cookieDomain = next;
      index += 1;
    }
  }

  return parsed;
}

function loadPrivateKey(args) {
  if (args.privateKeyFile) {
    return fs.readFileSync(args.privateKeyFile, 'utf8');
  }

  if (args.privateKeyBase64) {
    const decoded = Buffer.from(args.privateKeyBase64, 'base64').toString('utf8');
    return decoded.includes('BEGIN') ? decoded : Buffer.from(args.privateKeyBase64, 'base64');
  }

  if (process.env.CF_PRIVATE_KEY_PEM) {
    return process.env.CF_PRIVATE_KEY_PEM;
  }

  if (process.env.CF_PRIVATE_KEY_BASE64) {
    return Buffer.from(process.env.CF_PRIVATE_KEY_BASE64, 'base64').toString('utf8');
  }

  throw new Error('CloudFront private key is required');
}

function encodePolicy(policy) {
  return Buffer.from(policy, 'utf8').toString('base64').replace(/\n|\r/g, '');
}

function signPolicy(policy, privateKey) {
  const signer = crypto.createSign('RSA-SHA1');
  signer.update(policy, 'utf8');
  signer.end();
  return signer.sign(privateKey, 'base64').replace(/\n|\r/g, '');
}

function resolveResourceUrl(payload, args) {
  if (payload.resourceUrl) {
    return payload.resourceUrl;
  }

  if (payload.targetUrl) {
    return payload.targetUrl;
  }

  if (payload.resourcePath) {
    if (!args.distributionDomain) {
      throw new Error('distribution domain is required when resourcePath is used');
    }

    return `https://${args.distributionDomain}${payload.resourcePath}`;
  }

  throw new Error('resourceUrl, targetUrl, or resourcePath is required');
}

function buildPolicy(resourceUrl, expiresEpoch) {
  return JSON.stringify({
    Statement: [
      {
        Resource: resourceUrl,
        Condition: {
          DateLessThan: {
            'AWS:EpochTime': expiresEpoch
          }
        }
      }
    ]
  });
}

function collectBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk.toString();
    });
    req.on('end', () => resolve(body));
    req.on('error', reject);
  });
}

async function handleIssueCookie(req, res, args, privateKey) {
  const bodyText = await collectBody(req);
  const payload = bodyText ? JSON.parse(bodyText) : {};
  const resourceUrl = resolveResourceUrl(payload, args);
  const ttlSeconds = Number(payload.ttlSeconds || args.defaultTtlSeconds);
  const expiresEpoch = Math.floor(Date.now() / 1000) + ttlSeconds;
  const policy = buildPolicy(payload.resourcePattern || resourceUrl, expiresEpoch);
  const signature = signPolicy(policy, privateKey);
  const cookieDomain = payload.cookieDomain || args.cookieDomain || new URL(resourceUrl).hostname;
  const cookiePath = payload.cookiePath || args.cookiePath || '/';

  const response = {
    resourceUrl,
    expiresAt: new Date(expiresEpoch * 1000).toISOString(),
    ttlSeconds,
    cookieDomain,
    cookiePath,
    cookies: {
      'CloudFront-Policy': encodePolicy(policy),
      'CloudFront-Signature': signature,
      'CloudFront-Key-Pair-Id': args.keyPairId
    }
  };

  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(response));
}

async function main() {
  const args = parseArgs(process.argv);
  if (!args.keyPairId) {
    throw new Error('CloudFront key pair id is required');
  }

  const privateKey = loadPrivateKey(args);
  const server = http.createServer(async (req, res) => {
    try {
      if (req.method === 'GET' && req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true }));
        return;
      }

      if (req.method === 'POST' && req.url === '/issue-cookie') {
        await handleIssueCookie(req, res, args, privateKey);
        return;
      }

      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ message: 'Not Found' }));
    } catch (error) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ message: error.message }));
    }
  });

  server.listen(args.port, args.host, () => {
    console.log(`CloudFront cookie bootstrap server listening on http://${args.host}:${args.port}`);
  });
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
