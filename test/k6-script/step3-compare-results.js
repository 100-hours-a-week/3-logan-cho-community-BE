#!/usr/bin/env node

/**
 * 성능 테스트 결과 비교 도구
 *
 * 사용법:
 *   node compare-results.js performance-results/before-xxx.json performance-results/after-xxx.json
 *
 * 두 개의 K6 테스트 결과 JSON 파일을 비교하여 성능 개선율을 계산합니다.
 */

const fs = require('fs');
const path = require('path');

// CLI 인자 파싱
const args = process.argv.slice(2);

if (args.length < 2) {
  console.error('사용법: node compare-results.js <before.json> <after.json>');
  console.error('예시: node compare-results.js performance-results/before-2024-01-01.json performance-results/after-2024-01-01.json');
  process.exit(1);
}

const beforeFile = args[0];
const afterFile = args[1];

// 파일 읽기
let beforeData, afterData;

try {
  beforeData = JSON.parse(fs.readFileSync(beforeFile, 'utf8'));
  console.log(`✅ Before 파일 로드: ${beforeFile}`);
} catch (err) {
  console.error(`❌ Before 파일 읽기 실패: ${beforeFile}`);
  console.error(err.message);
  process.exit(1);
}

try {
  afterData = JSON.parse(fs.readFileSync(afterFile, 'utf8'));
  console.log(`✅ After 파일 로드: ${afterFile}`);
} catch (err) {
  console.error(`❌ After 파일 읽기 실패: ${afterFile}`);
  console.error(err.message);
  process.exit(1);
}

// 메트릭 비교 함수
function compareMetric(metricName, beforeMetrics, afterMetrics) {
  const before = beforeMetrics[metricName];
  const after = afterMetrics[metricName];

  if (!before || !after) {
    return null;
  }

  const result = {
    name: metricName,
    before: {},
    after: {},
    improvement: {},
  };

  // Duration 메트릭 비교
  if (before.values && after.values) {
    ['p(50)', 'p(95)', 'p(99)', 'avg', 'min', 'max'].forEach(percentile => {
      if (before.values[percentile] !== undefined && after.values[percentile] !== undefined) {
        const beforeVal = before.values[percentile];
        const afterVal = after.values[percentile];
        const improvement = ((beforeVal - afterVal) / beforeVal) * 100;

        result.before[percentile] = beforeVal;
        result.after[percentile] = afterVal;
        result.improvement[percentile] = improvement;
      }
    });

    // Rate 메트릭 비교 (성공률 등)
    if (before.values.rate !== undefined && after.values.rate !== undefined) {
      const beforeVal = before.values.rate * 100;
      const afterVal = after.values.rate * 100;
      const improvement = afterVal - beforeVal;  // Rate는 절대값 차이

      result.before.rate = beforeVal;
      result.after.rate = afterVal;
      result.improvement.rate = improvement;
    }

    // Counter 메트릭 비교 (에러 수 등)
    if (before.values.count !== undefined && after.values.count !== undefined) {
      const beforeVal = before.values.count;
      const afterVal = after.values.count;
      const improvement = beforeVal === 0 ? 0 : ((beforeVal - afterVal) / beforeVal) * 100;

      result.before.count = beforeVal;
      result.after.count = afterVal;
      result.improvement.count = improvement;
    }
  }

  return result;
}

// 주요 메트릭 목록
const keyMetrics = [
  'baseline_list_posts_duration',
  'baseline_post_detail_duration',
  'baseline_create_post_duration',
  'baseline_create_comment_duration',
  'baseline_like_post_duration',
  'baseline_login_duration',
  'baseline_list_posts_success',
  'baseline_post_detail_success',
  'baseline_create_post_success',
  'baseline_create_comment_success',
  'baseline_like_post_success',
  'http_req_duration',
  'http_req_failed',
];

// 비교 결과 출력
console.log('\n' + '='.repeat(80));
console.log('성능 개선 비교 결과');
console.log('='.repeat(80));

const beforeMetrics = beforeData.metrics;
const afterMetrics = afterData.metrics;

let significantImprovements = [];
let regressions = [];

keyMetrics.forEach(metricName => {
  const comparison = compareMetric(metricName, beforeMetrics, afterMetrics);

  if (!comparison) {
    return;
  }

  console.log(`\n📊 ${metricName}`);
  console.log('-'.repeat(80));

  Object.keys(comparison.improvement).forEach(key => {
    const beforeVal = comparison.before[key];
    const afterVal = comparison.after[key];
    const improvement = comparison.improvement[key];

    let unit = '';
    let format = (val) => val.toFixed(2);

    if (key === 'rate') {
      unit = '%';
      format = (val) => val.toFixed(2);
    } else if (key === 'count') {
      unit = '개';
      format = (val) => Math.round(val);
    } else {
      unit = 'ms';
      format = (val) => val.toFixed(2);
    }

    const improvementStr = improvement > 0
      ? `✅ ${improvement.toFixed(2)}% 개선`
      : improvement < 0
      ? `❌ ${Math.abs(improvement).toFixed(2)}% 저하`
      : '➖ 변화 없음';

    console.log(`  ${key.padEnd(10)}: ${format(beforeVal)}${unit} → ${format(afterVal)}${unit} (${improvementStr})`);

    // 유의미한 개선 (10% 이상)
    if (improvement > 10 && key !== 'rate') {
      significantImprovements.push({
        metric: metricName,
        percentile: key,
        improvement: improvement,
      });
    }

    // 성능 저하 (5% 이상)
    if (improvement < -5 && key !== 'rate') {
      regressions.push({
        metric: metricName,
        percentile: key,
        regression: Math.abs(improvement),
      });
    }
  });
});

// 전체 요약
console.log('\n' + '='.repeat(80));
console.log('📈 전체 요약');
console.log('='.repeat(80));

if (significantImprovements.length > 0) {
  console.log('\n✅ 주요 성능 개선 (10% 이상):');
  significantImprovements
    .sort((a, b) => b.improvement - a.improvement)
    .forEach((item, idx) => {
      console.log(`  ${idx + 1}. ${item.metric} (${item.percentile}): ${item.improvement.toFixed(2)}% 개선`);
    });
} else {
  console.log('\n➖ 10% 이상 개선된 메트릭이 없습니다.');
}

if (regressions.length > 0) {
  console.log('\n❌ 성능 저하 (5% 이상):');
  regressions
    .sort((a, b) => b.regression - a.regression)
    .forEach((item, idx) => {
      console.log(`  ${idx + 1}. ${item.metric} (${item.percentile}): ${item.regression.toFixed(2)}% 저하`);
    });
} else {
  console.log('\n✅ 성능 저하 항목이 없습니다.');
}

// 전반적인 성능 개선률 계산
const overallImprovement = significantImprovements.length > 0
  ? significantImprovements.reduce((sum, item) => sum + item.improvement, 0) / significantImprovements.length
  : 0;

console.log(`\n📊 전반적인 성능 개선률: ${overallImprovement.toFixed(2)}%`);

// 리소스 사용량 비교 (http_reqs, data_received, data_sent)
console.log('\n' + '='.repeat(80));
console.log('📦 리소스 사용량');
console.log('='.repeat(80));

const compareResource = (name, unit = '') => {
  const before = beforeMetrics[name]?.values?.count || 0;
  const after = afterMetrics[name]?.values?.count || 0;
  const diff = after - before;
  const diffPercent = before === 0 ? 0 : ((diff / before) * 100);

  console.log(`  ${name.padEnd(20)}: ${before}${unit} → ${after}${unit} (${diffPercent >= 0 ? '+' : ''}${diffPercent.toFixed(2)}%)`);
};

compareResource('http_reqs', '개');
compareResource('data_received', 'B');
compareResource('data_sent', 'B');

console.log('\n' + '='.repeat(80));
console.log('비교 완료');
console.log('='.repeat(80) + '\n');

// 결과를 마크다운 파일로 저장
const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
const reportFile = `performance-results/comparison-${timestamp}.md`;

let markdown = `# 성능 개선 비교 보고서\n\n`;
markdown += `**생성 시간**: ${new Date().toISOString()}\n\n`;
markdown += `**Before**: \`${beforeFile}\`\n\n`;
markdown += `**After**: \`${afterFile}\`\n\n`;
markdown += `---\n\n`;

markdown += `## 주요 성능 개선\n\n`;

if (significantImprovements.length > 0) {
  markdown += `| 순위 | 메트릭 | 백분위수 | 개선율 |\n`;
  markdown += `|------|--------|----------|--------|\n`;
  significantImprovements
    .sort((a, b) => b.improvement - a.improvement)
    .forEach((item, idx) => {
      markdown += `| ${idx + 1} | ${item.metric} | ${item.percentile} | ${item.improvement.toFixed(2)}% |\n`;
    });
} else {
  markdown += `개선 사항 없음\n`;
}

markdown += `\n## 성능 저하\n\n`;

if (regressions.length > 0) {
  markdown += `| 순위 | 메트릭 | 백분위수 | 저하율 |\n`;
  markdown += `|------|--------|----------|--------|\n`;
  regressions
    .sort((a, b) => b.regression - a.regression)
    .forEach((item, idx) => {
      markdown += `| ${idx + 1} | ${item.metric} | ${item.percentile} | ${item.regression.toFixed(2)}% |\n`;
    });
} else {
  markdown += `저하 사항 없음\n`;
}

markdown += `\n## 전반적인 결과\n\n`;
markdown += `- **전반적인 성능 개선률**: ${overallImprovement.toFixed(2)}%\n`;
markdown += `- **유의미한 개선 항목 수**: ${significantImprovements.length}개\n`;
markdown += `- **성능 저하 항목 수**: ${regressions.length}개\n`;

fs.writeFileSync(reportFile, markdown, 'utf8');
console.log(`📄 마크다운 보고서 저장: ${reportFile}\n`);