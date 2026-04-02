'use strict';

const fs = require('node:fs');
const path = require('node:path');

function resolveConfigPath(inputPath) {
  if (!inputPath) {
    return path.resolve(process.cwd(), 'configs', 'benchmark.config.json');
  }

  return path.resolve(process.cwd(), inputPath);
}

function loadConfig(inputPath) {
  const configPath = resolveConfigPath(inputPath);
  if (!fs.existsSync(configPath)) {
    throw new Error(`Config file not found: ${configPath}`);
  }

  const raw = fs.readFileSync(configPath, 'utf8');
  const config = JSON.parse(raw);

  if (!config.iterations || typeof config.iterations.miss !== 'number' || typeof config.iterations.hit !== 'number') {
    throw new Error('Config must define iterations.miss and iterations.hit as numbers');
  }

  if (!config.objectCases || typeof config.objectCases !== 'object') {
    throw new Error('Config must define objectCases');
  }

  return {
    config,
    configPath
  };
}

module.exports = {
  loadConfig,
  resolveConfigPath
};
