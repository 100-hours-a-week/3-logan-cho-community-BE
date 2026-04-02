'use strict';

const fs = require('node:fs');
const path = require('node:path');

function escapeCsvValue(value) {
  if (value === null || value === undefined) {
    return '';
  }

  const stringValue = String(value);
  if (/[",\n]/.test(stringValue)) {
    return `"${stringValue.replace(/"/g, '""')}"`;
  }

  return stringValue;
}

function writeCsv(filePath, rows, headers) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const headerLine = headers.map(escapeCsvValue).join(',');
  const dataLines = rows.map((row) =>
    headers.map((header) => escapeCsvValue(row[header])).join(',')
  );
  fs.writeFileSync(filePath, [headerLine, ...dataLines].join('\n') + '\n', 'utf8');
}

function parseCsvLine(line) {
  const values = [];
  let current = '';
  let inQuotes = false;

  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    const next = line[index + 1];

    if (char === '"' && inQuotes && next === '"') {
      current += '"';
      index += 1;
      continue;
    }

    if (char === '"') {
      inQuotes = !inQuotes;
      continue;
    }

    if (char === ',' && !inQuotes) {
      values.push(current);
      current = '';
      continue;
    }

    current += char;
  }

  values.push(current);
  return values;
}

function readCsv(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8').trim();
  if (!raw) {
    return [];
  }

  const lines = raw.split(/\r?\n/);
  const headers = parseCsvLine(lines[0]);

  return lines.slice(1).filter(Boolean).map((line) => {
    const values = parseCsvLine(line);
    return headers.reduce((accumulator, header, index) => {
      accumulator[header] = values[index] || '';
      return accumulator;
    }, {});
  });
}

module.exports = {
  writeCsv,
  readCsv
};
