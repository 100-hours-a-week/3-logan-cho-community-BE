'use strict';

function toNumber(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function average(values) {
  if (!values.length) {
    return null;
  }

  const sum = values.reduce((accumulator, value) => accumulator + value, 0);
  return sum / values.length;
}

function percentile(values, percentileValue) {
  if (!values.length) {
    return null;
  }

  const sorted = [...values].sort((left, right) => left - right);
  const rank = (percentileValue / 100) * (sorted.length - 1);
  const lower = Math.floor(rank);
  const upper = Math.ceil(rank);

  if (lower === upper) {
    return sorted[lower];
  }

  const weight = rank - lower;
  return sorted[lower] * (1 - weight) + sorted[upper] * weight;
}

function summarizeMetric(rows, fieldName) {
  const values = rows.map((row) => toNumber(row[fieldName])).filter((value) => value !== null);
  return {
    avg: average(values),
    p50: percentile(values, 50),
    p95: percentile(values, 95)
  };
}

function formatNumber(value) {
  if (value === null || value === undefined) {
    return '';
  }

  return Number(value).toFixed(6);
}

module.exports = {
  average,
  percentile,
  summarizeMetric,
  formatNumber,
  toNumber
};
