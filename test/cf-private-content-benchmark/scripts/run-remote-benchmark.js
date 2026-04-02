#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { loadConfig } = require('./utils/configLoader');
const { buildMatrix, buildRoundRobinSchedule, CACHE_PHASES } = require('./utils/matrixBuilder');
const { writeCsv } = require('./utils/csvWriter');
const { runCurl } = require('./utils/curlRunner');

const RAW_HEADERS = [
  'run_id',
  'timestamp',
  'location',
  'hostname',
  'cache_phase',
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

function parseArgs(argv) {
  const parsed = {
    config: null,
    phase: 'all',
    location: 'azure_busan',
    rawDir: path.resolve(process.cwd(), 'results', 'raw')
  };

  for (let index = 2; index < argv.length; index += 1) {
    const token = argv[index];
    const next = argv[index + 1];

    if (token === '--config' && next) {
      parsed.config = next;
      index += 1;
      continue;
    }

    if (token === '--phase' && next) {
      parsed.phase = next;
      index += 1;
      continue;
    }

    if (token === '--location' && next) {
      parsed.location = next;
      index += 1;
      continue;
    }

    if (token === '--raw-dir' && next) {
      parsed.rawDir = path.resolve(process.cwd(), next);
      index += 1;
    }
  }

  return parsed;
}

function timestampSlug(date = new Date()) {
  return date.toISOString().replace(/[:.]/g, '-');
}

function makeRunId(location) {
  return `${location}-${timestampSlug()}`;
}

function createRow(base, metrics) {
  return {
    run_id: base.runId,
    timestamp: new Date().toISOString(),
    location: base.location,
    hostname: base.hostname,
    cache_phase: base.cachePhase,
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

async function executePhase({ config, location, phase, hostname, rawDir, runId }) {
  const groups = buildMatrix(config, location, phase);
  if (!groups.length) {
    return null;
  }

  const rows = [];

  if (phase === 'hit') {
    for (const group of groups) {
      const metrics = await runCurl(group.entries[0]);
      rows.push(createRow({
        runId,
        location,
        hostname,
        cachePhase: phase,
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
    const metrics = await runCurl(item.entry);
    rows.push(createRow({
      runId,
      location,
      hostname,
      cachePhase: item.cachePhase,
      objectSizeCase: item.objectSizeCase,
      deliveryType: item.deliveryType,
      objectId: item.entry.objectId,
      iteration: item.iteration,
      primed: false,
      urlLabel: item.entry.label
    }, metrics));
  }

  fs.mkdirSync(rawDir, { recursive: true });
  const filePath = path.join(rawDir, `raw-${location}-${hostname}-${phase}-${timestampSlug()}.csv`);
  writeCsv(filePath, rows, RAW_HEADERS);
  return filePath;
}

async function main() {
  const args = parseArgs(process.argv);
  const { config } = loadConfig(args.config);
  const hostname = os.hostname();
  const runId = makeRunId(args.location);
  const phases = args.phase === 'all' ? CACHE_PHASES : [args.phase];
  const outputs = [];

  for (const phase of phases) {
    const filePath = await executePhase({
      config,
      location: args.location,
      phase,
      hostname,
      rawDir: args.rawDir,
      runId
    });

    if (filePath) {
      outputs.push(filePath);
      console.log(`Wrote raw results: ${filePath}`);
    }
  }

  if (!outputs.length) {
    console.warn('No benchmark groups were created for the selected location/phase');
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
