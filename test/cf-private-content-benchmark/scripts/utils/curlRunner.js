'use strict';

const { spawn } = require('node:child_process');

const CURL_FORMAT = JSON.stringify({
  http_code: '%{http_code}',
  time_namelookup: '%{time_namelookup}',
  time_connect: '%{time_connect}',
  time_appconnect: '%{time_appconnect}',
  time_starttransfer: '%{time_starttransfer}',
  time_total: '%{time_total}',
  size_download: '%{size_download}',
  remote_ip: '%{remote_ip}'
});

function runCurl(request) {
  return new Promise((resolve, reject) => {
    const args = [
      '--silent',
      '--show-error',
      '--location',
      '--output',
      request.outputFile || '/dev/null',
      '--write-out',
      CURL_FORMAT
    ];

    if (request.method) {
      args.push('--request', request.method);
    }

    if (request.headers && Array.isArray(request.headers)) {
      for (const header of request.headers) {
        args.push('--header', header);
      }
    }

    if (request.cookieHeader) {
      args.push('--header', `Cookie: ${request.cookieHeader}`);
    }

    if (request.cookieFile) {
      args.push('--cookie', request.cookieFile);
    }

    if (request.cookieJarFile) {
      args.push('--cookie-jar', request.cookieJarFile);
    }

    if (request.body !== undefined) {
      args.push('--data-raw', request.body);
    }

    args.push(request.url);

    const child = spawn('curl', args, {
      stdio: ['ignore', 'pipe', 'pipe']
    });

    let stdout = '';
    let stderr = '';

    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString();
    });

    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });

    child.on('error', reject);

    child.on('close', (code) => {
      let parsed = {
        http_code: code === 0 ? '' : '000',
        time_namelookup: '',
        time_connect: '',
        time_appconnect: '',
        time_starttransfer: '',
        time_total: '',
        size_download: '',
        remote_ip: ''
      };

      if (stdout.trim()) {
        try {
          parsed = JSON.parse(stdout.trim());
        } catch (error) {
          return reject(new Error(`Failed to parse curl output: ${stdout.trim()}`));
        }
      }

      if (code !== 0) {
        parsed.curl_error = stderr.trim() || `curl exited with ${code}`;
      }

      return resolve(parsed);
    });
  });
}

module.exports = {
  runCurl
};
