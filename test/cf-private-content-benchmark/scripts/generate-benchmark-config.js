#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const crypto = require('node:crypto');

function parseArgs(argv) {
  const parsed = {
    terraformDir: path.resolve(process.cwd(), 'terraform'),
    outputPath: path.resolve(process.cwd(), 'configs', 'benchmark.config.json'),
    bootstrapUrl: 'http://127.0.0.1:3100/issue-cookie',
    location: 'local_gyeonggi'
  };

  for (let index = 2; index < argv.length; index += 1) {
    const token = argv[index];
    const next = argv[index + 1];

    if (token === '--terraform-dir' && next) {
      parsed.terraformDir = path.resolve(process.cwd(), next);
      index += 1;
      continue;
    }

    if (token === '--output' && next) {
      parsed.outputPath = path.resolve(process.cwd(), next);
      index += 1;
      continue;
    }

    if (token === '--bootstrap-url' && next) {
      parsed.bootstrapUrl = next;
      index += 1;
      continue;
    }

    if (token === '--location' && next) {
      parsed.location = next;
      index += 1;
    }
  }

  return parsed;
}

function terraformOutput(terraformDir) {
  return JSON.parse(execFileSync('terraform', ['output', '-json'], {
    cwd: terraformDir,
    encoding: 'utf8'
  }));
}

function outputValue(outputs, name) {
  if (!outputs[name]) {
    throw new Error(`Terraform output not found: ${name}`);
  }

  return outputs[name].value;
}

function signCloudFrontUrl({ url, keyPairId, privateKeyPem, expiresEpoch }) {
  const policy = JSON.stringify({
    Statement: [
      {
        Resource: url,
        Condition: {
          DateLessThan: {
            'AWS:EpochTime': expiresEpoch
          }
        }
      }
    ]
  });

  const signer = crypto.createSign('RSA-SHA1');
  signer.update(policy, 'utf8');
  signer.end();

  const signature = signer.sign(privateKeyPem, 'base64').replace(/\n|\r/g, '');
  const encodedPolicy = Buffer.from(policy, 'utf8').toString('base64').replace(/\n|\r/g, '');
  const signedUrl = new URL(url);
  signedUrl.searchParams.set('Policy', encodedPolicy);
  signedUrl.searchParams.set('Signature', signature);
  signedUrl.searchParams.set('Key-Pair-Id', keyPairId);
  return signedUrl.toString();
}

function presignS3Url({ bucket, key, region, ttlSeconds }) {
  return execFileSync('aws', [
    's3',
    'presign',
    `s3://${bucket}/${key}`,
    '--expires-in',
    String(ttlSeconds),
    '--region',
    region
  ], {
    encoding: 'utf8'
  }).trim();
}

function mapEntries(entries, mapper) {
  return entries.map((entry) => mapper(entry));
}

function buildConfig({ outputs, args }) {
  const bucketName = outputValue(outputs, 'experiment_bucket_name');
  const cloudFrontDomain = outputValue(outputs, 'experiment_cloudfront_domain_name');
  const keyPairId = outputValue(outputs, 'experiment_cloudfront_public_key_id');
  const privateKeyPemPath = outputValue(outputs, 'experiment_private_key_pem_path');
  const objectManifest = outputValue(outputs, 'experiment_object_manifest');
  const missIterations = outputValue(outputs, 'benchmark_miss_iterations');
  const hitIterations = outputValue(outputs, 'benchmark_hit_iterations');
  const signedUrlTtlSeconds = outputValue(outputs, 'signed_url_ttl_seconds');
  const cookieTtlSecondsMiss = outputValue(outputs, 'cookie_ttl_seconds_miss');
  const cookieTtlSecondsHit = outputValue(outputs, 'cookie_ttl_seconds_hit');
  const awsRegion = outputValue(outputs, 'experiment_aws_region');
  const privateKeyPem = fs.readFileSync(privateKeyPemPath, 'utf8');
  const expiresEpoch = Math.floor(Date.now() / 1000) + Number(signedUrlTtlSeconds);

  const objectCases = {};

  for (const [sizeCase, caseManifest] of Object.entries(objectManifest)) {
    const buildPhase = (phaseName) => {
      const sourceEntries = caseManifest[phaseName];
      const cookieTtl = phaseName === 'miss' ? cookieTtlSecondsMiss : cookieTtlSecondsHit;

      return {
        s3_presigned: mapEntries(sourceEntries, (entry) => ({
          url: presignS3Url({
            bucket: bucketName,
            key: entry.key,
            region: awsRegion,
            ttlSeconds: signedUrlTtlSeconds
          }),
          label: `s3-${entry.label}`,
          objectId: entry.objectId
        })),
        cf_signed_url: mapEntries(sourceEntries, (entry) => ({
          url: signCloudFrontUrl({
            url: `https://${cloudFrontDomain}/${entry.key}`,
            keyPairId,
            privateKeyPem,
            expiresEpoch
          }),
          label: `cf-url-${entry.label}`,
          objectId: entry.objectId
        })),
        cf_signed_cookie: mapEntries(sourceEntries, (entry) => ({
          targetUrl: `https://${cloudFrontDomain}/${entry.key}`,
          bootstrap: {
            url: args.bootstrapUrl,
            resourcePath: `/${entry.key}`,
            cookieDomain: cloudFrontDomain,
            ttlSeconds: cookieTtl,
            label: 'terraform-cookie-bootstrap'
          },
          label: `cf-cookie-${entry.label}`,
          objectId: entry.objectId
        }))
      };
    };

    objectCases[sizeCase] = {
      description: `${sizeCase} object generated by Terraform`,
      miss: buildPhase('miss'),
      hit: buildPhase('hit')
    };
  }

  return {
    locations: [args.location],
    iterations: {
      miss: missIterations,
      hit: hitIterations
    },
    generatedFromTerraform: {
      bucketName,
      cloudFrontDomain,
      keyPairId,
      privateKeyPemPath,
      bootstrapUrl: args.bootstrapUrl
    },
    objectCases
  };
}

function main() {
  const args = parseArgs(process.argv);
  const outputs = terraformOutput(args.terraformDir);
  const config = buildConfig({ outputs, args });
  fs.mkdirSync(path.dirname(args.outputPath), { recursive: true });
  fs.writeFileSync(args.outputPath, JSON.stringify(config, null, 2) + '\n', 'utf8');
  console.log(`Wrote benchmark config: ${args.outputPath}`);
}

main();
