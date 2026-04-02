'use strict';

const fs = require('node:fs');
const path = require('node:path');

const { buildMatrix, buildRoundRobinSchedule } = require('./matrixBuilder');
const { writeCsv } = require('./csvWriter');
const { runCurl } = require('./curlRunner');
const { issueBootstrapCookie, cleanupCookieFile } = require('./cookieBootstrap');

const RAW_HEADERS = [
  'run_id',
  'timestamp',
  'location',
  'hostname',
  'cache_phase',
  'measurement_stage',
  'object_size_case',
  'delivery_type',
  'object_id',
  'iteration',
  'primed',
  'http_code',
  'time_namelookup',
  'time_connect',
  'time_appconnect',
  'time_starttransfer',
  'time_total',
  'size_download',
  'remote_ip',
  'url_label'
];

function timestampSlug(date = new Date()) {
  return date.toISOString().replace(/[:.]/g, '-');
}

function createRow(base, metrics) {
  return {
    run_id: base.runId,
    timestamp: new Date().toISOString(),
    location: base.location,
    hostname: base.hostname,
    cache_phase: base.cachePhase,
    measurement_stage: base.measurementStage,
    object_size_case: base.objectSizeCase,
    delivery_type: base.deliveryType,
    object_id: base.objectId,
    iteration: base.iteration,
    primed: String(base.primed),
    http_code: metrics.http_code || '',
    time_namelookup: metrics.time_namelookup || '',
    time_connect: metrics.time_connect || '',
    time_appconnect: metrics.time_appconnect || '',
    time_starttransfer: metrics.time_starttransfer || '',
    time_total: metrics.time_total || '',
    size_download: metrics.size_download || '',
    remote_ip: metrics.remote_ip || '',
    url_label: base.urlLabel
  };
}

async function runAssetFetch(entry, cookieFile) {
  return runCurl({
    url: entry.url,
    cookieHeader: entry.cookieHeader,
    cookieFile: cookieFile || entry.cookieFile
  });
}

async function prepareCookieForEntry({ entry, rows, rowBase, iteration }) {
  if (entry.bootstrap) {
    const bootstrapResult = await issueBootstrapCookie(entry);
    rows.push(createRow({
      ...rowBase,
      measurementStage: 'bootstrap',
      iteration,
      primed: false,
      urlLabel: bootstrapResult.bootstrapLabel
    }, bootstrapResult.metrics));

    return bootstrapResult.cookieFilePath;
  }

  return null;
}

async function executePhase({ config, location, phase, hostname, rawDir, runId, fileNamePrefix }) {
  const groups = buildMatrix(config, location, phase);
  if (!groups.length) {
    return null;
  }

  const rows = [];
  const sharedCookieFiles = new Map();

  if (phase === 'hit') {
    for (const group of groups) {
      let cookieFile = null;
      if (group.deliveryType === 'cf_signed_cookie' && group.entries[0].bootstrap) {
        cookieFile = await prepareCookieForEntry({
          entry: group.entries[0],
          rows,
          rowBase: {
            runId,
            location,
            hostname,
            cachePhase: phase,
            objectSizeCase: group.objectSizeCase,
            deliveryType: group.deliveryType,
            objectId: group.entries[0].objectId
          },
          iteration: 0
        });
        sharedCookieFiles.set(`${group.objectSizeCase}::${group.deliveryType}`, cookieFile);
      }

      const metrics = await runAssetFetch(group.entries[0], cookieFile);
      rows.push(createRow({
        runId,
        location,
        hostname,
        cachePhase: phase,
        measurementStage: 'asset_fetch',
        objectSizeCase: group.objectSizeCase,
        deliveryType: group.deliveryType,
        objectId: group.entries[0].objectId,
        iteration: 0,
        primed: true,
        urlLabel: group.entries[0].label
      }, metrics));
    }
  }

  const schedule = buildRoundRobinSchedule(groups, phase);
  for (const item of schedule) {
    let cookieFile = null;
    const sharedCookieKey = `${item.objectSizeCase}::${item.deliveryType}`;

    if (item.deliveryType === 'cf_signed_cookie') {
      if (phase === 'hit' && sharedCookieFiles.has(sharedCookieKey)) {
        cookieFile = sharedCookieFiles.get(sharedCookieKey);
      } else if (item.entry.bootstrap) {
        cookieFile = await prepareCookieForEntry({
          entry: item.entry,
          rows,
          rowBase: {
            runId,
            location,
            hostname,
            cachePhase: item.cachePhase,
            objectSizeCase: item.objectSizeCase,
            deliveryType: item.deliveryType,
            objectId: item.entry.objectId
          },
          iteration: item.iteration
        });
      }
    }

    try {
      const metrics = await runAssetFetch(item.entry, cookieFile);
      rows.push(createRow({
        runId,
        location,
        hostname,
        cachePhase: item.cachePhase,
        measurementStage: 'asset_fetch',
        objectSizeCase: item.objectSizeCase,
        deliveryType: item.deliveryType,
        objectId: item.entry.objectId,
        iteration: item.iteration,
        primed: false,
        urlLabel: item.entry.label
      }, metrics));
    } finally {
      if (phase !== 'hit') {
        cleanupCookieFile(cookieFile);
      }
    }
  }

  for (const cookieFile of sharedCookieFiles.values()) {
    cleanupCookieFile(cookieFile);
  }

  fs.mkdirSync(rawDir, { recursive: true });
  const filePath = path.join(rawDir, `${fileNamePrefix}-${location}-${phase}-${timestampSlug()}.csv`);
  writeCsv(filePath, rows, RAW_HEADERS);
  return filePath;
}

module.exports = {
  RAW_HEADERS,
  executePhase
};
