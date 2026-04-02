'use strict';

const { URL } = require('node:url');

const DELIVERY_TYPES = ['s3_presigned', 'cf_signed_url', 'cf_signed_cookie'];
const CACHE_PHASES = ['miss', 'hit'];

function deriveLabel(rawValue, deliveryType, objectSizeCase, cachePhase, index) {
  if (typeof rawValue === 'string') {
    try {
      const parsed = new URL(rawValue);
      const fileName = parsed.pathname.split('/').filter(Boolean).pop() || `item-${index + 1}`;
      return `${deliveryType}-${objectSizeCase}-${cachePhase}-${fileName}`;
    } catch (error) {
      return `${deliveryType}-${objectSizeCase}-${cachePhase}-${index + 1}`;
    }
  }

  if (rawValue.label) {
    return rawValue.label;
  }

  const source = rawValue.url || rawValue.targetUrl || `item-${index + 1}`;
  try {
    const parsed = new URL(source);
    const fileName = parsed.pathname.split('/').filter(Boolean).pop() || `item-${index + 1}`;
    return `${deliveryType}-${objectSizeCase}-${cachePhase}-${fileName}`;
  } catch (error) {
    return `${deliveryType}-${objectSizeCase}-${cachePhase}-${index + 1}`;
  }
}

function normalizeEntry(rawValue, deliveryType, objectSizeCase, cachePhase, index) {
  if (typeof rawValue === 'string') {
    return {
      url: rawValue,
      label: deriveLabel(rawValue, deliveryType, objectSizeCase, cachePhase, index),
      objectId: `${objectSizeCase}-${cachePhase}-${index + 1}`
    };
  }

  const url = rawValue.url || rawValue.targetUrl;
  if (!url) {
    throw new Error(`Missing url/targetUrl for ${deliveryType} ${objectSizeCase} ${cachePhase} entry ${index}`);
  }

  return {
    url,
    label: deriveLabel(rawValue, deliveryType, objectSizeCase, cachePhase, index),
    objectId: rawValue.objectId || `${objectSizeCase}-${cachePhase}-${index + 1}`,
    cookieHeader: rawValue.cookieHeader,
    cookieFile: rawValue.cookieFile,
    bootstrap: rawValue.bootstrap || null,
    bootstrapLabel: rawValue.bootstrapLabel || null
  };
}

function buildMatrix(config, location, requestedPhase) {
  if (config.locations && Array.isArray(config.locations) && !config.locations.includes(location)) {
    throw new Error(`Location "${location}" is not listed in config.locations`);
  }

  const phases = requestedPhase === 'all' ? CACHE_PHASES : [requestedPhase];
  const groups = [];

  for (const cachePhase of phases) {
    for (const [objectSizeCase, caseConfig] of Object.entries(config.objectCases)) {
      for (const deliveryType of DELIVERY_TYPES) {
        const entries = (((caseConfig || {})[cachePhase] || {})[deliveryType]) || [];
        if (!entries.length) {
          continue;
        }

        const normalizedEntries = entries.map((entry, index) =>
          normalizeEntry(entry, deliveryType, objectSizeCase, cachePhase, index)
        );
        const iterations = Number(config.iterations[cachePhase]);

        if (cachePhase === 'miss' && normalizedEntries.length < iterations) {
          throw new Error(
            `Not enough fresh objects for miss group ${objectSizeCase}/${deliveryType}. ` +
            `Need at least ${iterations}, got ${normalizedEntries.length}`
          );
        }

        groups.push({
          location,
          cachePhase,
          objectSizeCase,
          deliveryType,
          iterations,
          entries: normalizedEntries
        });
      }
    }
  }

  return groups;
}

function buildRoundRobinSchedule(groups, cachePhase) {
  const schedule = [];

  if (cachePhase === 'miss') {
    const maxIterations = Math.max(...groups.map((group) => group.iterations), 0);
    for (let index = 0; index < maxIterations; index += 1) {
      for (const group of groups) {
        if (index >= group.iterations) {
          continue;
        }

        schedule.push({
          ...group,
          iteration: index + 1,
          entry: group.entries[index],
          primed: false
        });
      }
    }
    return schedule;
  }

  const maxIterations = Math.max(...groups.map((group) => group.iterations), 0);
  for (let index = 0; index < maxIterations; index += 1) {
    for (const group of groups) {
      if (index >= group.iterations) {
        continue;
      }

      schedule.push({
        ...group,
        iteration: index + 1,
        entry: group.entries[0],
        primed: false
      });
    }
  }

  return schedule;
}

module.exports = {
  buildMatrix,
  buildRoundRobinSchedule,
  CACHE_PHASES,
  DELIVERY_TYPES
};
