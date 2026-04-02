#!/usr/bin/env node
'use strict';

const os = require('node:os');
const path = require('node:path');

const { loadConfig } = require('./utils/configLoader');
const { CACHE_PHASES } = require('./utils/matrixBuilder');
const { executePhase } = require('./utils/benchmarkRuntime');

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

function makeRunId(location) {
  return `${location}-${new Date().toISOString().replace(/[:.]/g, '-')}`;
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
      runId,
      fileNamePrefix: `raw-${hostname}`
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
