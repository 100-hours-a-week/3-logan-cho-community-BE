#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const { readCsv, writeCsv } = require('./utils/csvWriter');
const { summarizeMetric, formatNumber } = require('./utils/stats');

const SUMMARY_HEADERS = [
  'location',
  'cache_phase',
  'object_size_case',
  'delivery_type',
  'count',
  'avg_time_namelookup',
  'p50_time_namelookup',
  'p95_time_namelookup',
  'avg_time_connect',
  'p50_time_connect',
  'p95_time_connect',
  'avg_time_appconnect',
  'p50_time_appconnect',
  'p95_time_appconnect',
  'avg_time_starttransfer',
  'p50_time_starttransfer',
  'p95_time_starttransfer',
  'avg_time_total',
  'p50_time_total',
  'p95_time_total'
];

function parseArgs(argv) {
  const parsed = {
    rawDir: path.resolve(process.cwd(), 'results', 'raw'),
    summaryDir: path.resolve(process.cwd(), 'results', 'summary')
  };

  for (let index = 2; index < argv.length; index += 1) {
    const token = argv[index];
    const next = argv[index + 1];

    if (token === '--raw-dir' && next) {
      parsed.rawDir = path.resolve(process.cwd(), next);
      index += 1;
      continue;
    }

    if (token === '--summary-dir' && next) {
      parsed.summaryDir = path.resolve(process.cwd(), next);
      index += 1;
    }
  }

  return parsed;
}

function timestampSlug(date = new Date()) {
  return date.toISOString().replace(/[:.]/g, '-');
}

function listRawFiles(rawDir) {
  if (!fs.existsSync(rawDir)) {
    return [];
  }

  return fs.readdirSync(rawDir)
    .filter((fileName) => fileName.endsWith('.csv'))
    .map((fileName) => path.join(rawDir, fileName));
}

function buildGroups(rows) {
  const groups = new Map();

  for (const row of rows) {
    if (row.primed === 'true') {
      continue;
    }

    const key = [
      row.location,
      row.cache_phase,
      row.object_size_case,
      row.delivery_type
    ].join('|');

    if (!groups.has(key)) {
      groups.set(key, []);
    }

    groups.get(key).push(row);
  }

  return groups;
}

function summarizeGroups(groups) {
  const summaries = [];

  for (const [key, rows] of groups.entries()) {
    const [location, cachePhase, objectSizeCase, deliveryType] = key.split('|');
    const nameLookup = summarizeMetric(rows, 'time_namelookup');
    const connect = summarizeMetric(rows, 'time_connect');
    const appConnect = summarizeMetric(rows, 'time_appconnect');
    const startTransfer = summarizeMetric(rows, 'time_starttransfer');
    const total = summarizeMetric(rows, 'time_total');

    summaries.push({
      location,
      cache_phase: cachePhase,
      object_size_case: objectSizeCase,
      delivery_type: deliveryType,
      count: rows.length,
      avg_time_namelookup: formatNumber(nameLookup.avg),
      p50_time_namelookup: formatNumber(nameLookup.p50),
      p95_time_namelookup: formatNumber(nameLookup.p95),
      avg_time_connect: formatNumber(connect.avg),
      p50_time_connect: formatNumber(connect.p50),
      p95_time_connect: formatNumber(connect.p95),
      avg_time_appconnect: formatNumber(appConnect.avg),
      p50_time_appconnect: formatNumber(appConnect.p50),
      p95_time_appconnect: formatNumber(appConnect.p95),
      avg_time_starttransfer: formatNumber(startTransfer.avg),
      p50_time_starttransfer: formatNumber(startTransfer.p50),
      p95_time_starttransfer: formatNumber(startTransfer.p95),
      avg_time_total: formatNumber(total.avg),
      p50_time_total: formatNumber(total.p50),
      p95_time_total: formatNumber(total.p95)
    });
  }

  summaries.sort((left, right) => {
    return (
      left.location.localeCompare(right.location) ||
      left.cache_phase.localeCompare(right.cache_phase) ||
      left.object_size_case.localeCompare(right.object_size_case) ||
      left.delivery_type.localeCompare(right.delivery_type)
    );
  });

  return summaries;
}

function writeOutputs(summaryDir, summaries, filePrefix) {
  fs.mkdirSync(summaryDir, { recursive: true });
  const slug = timestampSlug();
  const csvPath = path.join(summaryDir, `${filePrefix}-${slug}.csv`);
  const jsonPath = path.join(summaryDir, `${filePrefix}-${slug}.json`);
  writeCsv(csvPath, summaries, SUMMARY_HEADERS);
  fs.writeFileSync(jsonPath, JSON.stringify(summaries, null, 2) + '\n', 'utf8');
  return { csvPath, jsonPath };
}

function main() {
  const args = parseArgs(process.argv);
  const rawFiles = listRawFiles(args.rawDir);
  const allRows = rawFiles.flatMap((filePath) => readCsv(filePath));
  const groups = buildGroups(allRows);
  const summaries = summarizeGroups(groups);

  const allOutputs = writeOutputs(args.summaryDir, summaries, 'summary-all');
  console.log(`Wrote summary CSV: ${allOutputs.csvPath}`);
  console.log(`Wrote summary JSON: ${allOutputs.jsonPath}`);

  for (const cachePhase of ['miss', 'hit']) {
    const phaseRows = summaries.filter((row) => row.cache_phase === cachePhase);
    const outputs = writeOutputs(args.summaryDir, phaseRows, `summary-${cachePhase}`);
    console.log(`Wrote ${cachePhase} summary CSV: ${outputs.csvPath}`);
    console.log(`Wrote ${cachePhase} summary JSON: ${outputs.jsonPath}`);
  }
}

main();
