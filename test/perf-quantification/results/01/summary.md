# 실험 01 요약

## 근본 목적
좋아요 삭제(탈퇴) 트랜잭션이 member_id 인덱스 미보유/보유 시 insert 지연과 락 대기 지표에 미치는 영향을 대용량 데이터에서 확인

## 비목적
실험 구조/스키마 변경이나 앱 구조 리펙토링은 제외하고, 락 지표 수집 및 insert 프로브 방식만 비교한다.

## 실험 조건
- 테이블 행 수: `5000000`
- 고유 사용자 수: `100000`
- 동시 탈퇴 사용자 수: `100,500,1000`
- 락 보유 시간: `8s`
- insert 횟수(프로파일당): `300`
- insert 락 타임아웃: `3s`

## 원시 지표

| mode | withdrawers | insert_avg_ms | insert_p50_ms | insert_p95_ms | insert_p99_ms | insert_timeout_rate | lock_waits_delta | lock_time_delta | max_innodb_lock_wait_rows | max_innodb_trx_wait_rows |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| without_idx | 100 | 191.01 | 27.00 | 1890.00 | 3054.00 | 0.0400 | 117 | 4930578 | 0 | 100 |
| with_idx | 100 | 103.37 | 27.00 | 46.00 | 3058.00 | 0.0200 | 64 | 814658 | 0 | 55 |
| without_idx | 500 | 100.05 | 17.00 | 61.00 | 3045.00 | 0.6767 | 150 | 6995444 | 0 | 140 |
| with_idx | 500 | 21.55 | 16.00 | 35.00 | 53.00 | 0.5500 | 91 | 1886814 | 0 | 74 |
| without_idx | 1000 | 69.40 | 13.00 | 37.00 | 3029.00 | 0.7967 | 147 | 7033227 | 0 | 140 |
| with_idx | 1000 | 24.32 | 24.00 | 46.00 | 74.00 | 0.4233 | 106 | 3091377 | 0 | 103 |

## A/B 비교(동일 컨커런시 기준)

개선률은 with_idx를 without_idx 기준으로 계산(양수면 개선).
| withdrawers | with_idx/without_idx insert_p95(%) | with_idx/without_idx lock_waits_delta(%) |
|---:|---:|---:|
| 100 | 97.57% | 45.30% |
| 500 | 42.62% | 39.33% |
| 1000 | -24.32% | 27.89% |

## 해석
- 프로파일별로 with_idx 모드의 삽입 p95가 낮고 Timeout 비율이 줄어들면 member_id 인덱스의 경합 완화 효과가 재현된 것으로 본다.
- max_innodb_lock_wait_rows/max_innodb_trx_wait_rows는 락 대기 관측용 보조 지표다.
