# 성능 정량화 결과 정리 (현재 실행 범위: 01,03,05)

## 근본 목적

01/03/05 실험의 목적을 PR에서 바로 확인할 수 있도록 실험 조건, 수치, 해석을 단일 레퍼런스로 정리한다.

## 비목적

- 코드·인프라 아키텍처 변경(서비스 코드 리펙터링, 클라우드 인프라 확장) 없이 실험 체계의 계측과 결과 정리에 집중한다.

## 개요

- 작성일: 2026-03-04
- 저장소 경로: `test/perf-quantification/results/*`
- 이번 PR 대상 실험: `01`, `03`, `05`만 실행·재정리
- `02`, `04`, `06`은 실행군에서 제외(보존 스크립트는 별도 참조)

## 실험 01 — Next-Key Lock 범위 축소

- 핵심 의도: 좋아요 탈퇴(갱신) 동시성 상황에서 `member_id` 인덱스 유무가 insert 대기 지연/락 대기에 미치는 영향 정량화
- 실행 스크립트: `./scripts/run-exp01-next-key-lock.sh`
- 주요 실험 조건
  - 기본 데이터: `NEXTKEY_ROWS=5000000`
  - 고유 사용자: `NEXTKEY_UNIQUE_MEMBERS=100000`
  - 동시 탈퇴 사용자 후보: `NEXTKEY_WITHDRAW_CONCURRENCIES=100,500,1000` (필요 시 `250` 포함 테스트 가능)
  - 락 보유: `NEXTKEY_HOLD_SECONDS=8`
  - insert 반복: `NEXTKEY_INSERT_REPEAT=300`
  - insert 락 타임아웃: `NEXTKEY_LOCK_TIMEOUT_SECONDS=3`

### 실행 방식
- `next_key_likes_lock_test`를 500만행으로 재생성
- `member_id` 인덱스:
  - `without_idx`: `idx_member_deleted` 제거
  - `with_idx`: `idx_member_deleted(member_id, deleted_at)` 추가
- 동시 탈퇴 워커(100/500/1000명) 실행 중, 별도 insert 프로브를 동시 수행
- `Innodb_row_lock_waits`, `Innodb_row_lock_time`, insert p95, timeout율, lock wait 샘플(초 단위) 수집

### 실측 결과 (동일 조건 단일 실행)

- 단일 실행 원본: `./results/01/raw-01.csv`
- 실행일자: 2026-03-04

`results/01/raw-01.csv`(최신 1회):

| 동시 탈퇴 | without_idx(p95 / timeout / lock_wait_delta) | with_idx(p95 / timeout / lock_wait_delta) |
|---|---:|---:|
| 100 | 1890 / 0.0400 / 117 | 46 / 0.0200 / 64 |
| 500 | 61 / 0.6767 / 150 | 35 / 0.5500 / 91 |
| 1000 | 37 / 0.7967 / 147 | 46 / 0.4233 / 106 |

해석:
- `with_idx`는 timeout률과 lock_wait_delta 지표에서 전 구간 개선(락 확장 범위 축소)을 보여줌
- p95는 100/1000 구간에서 낮아졌고, 500 구간에서는 개선, 1000 구간은 증가로 분산 변동 존재

권고:
- PR 본문에는 500만행 단일 실행 기반 지표를 1차 반영하고, p95 변동이 큰 구간은 추가 반복(3회+)로 보정

## 실험 03 — 조회수 배치 반영(쓰기 부하)

- 핵심 의도: 조회수 즉시 반영 대비 배치 반영 시 MongoDB write 부하 감소 검증
- 실행 스크립트: `./scripts/run-exp03-view-counter-batch.sh`
- 핵심 산출물
  - k6 상세 조회 p95
  - `before`/`after` `opcounters.update` delta
- 실행 조건
  - `K6_VUS=20`, `K6_DURATION=1m`, `K6_SCENARIO=view_burst`
  - `BASE_URL=http://host.docker.internal:8080`
  - `MONGO_URI=mongodb://127.0.0.1:27017`
- 측정값
  - 상세 조회 p95: `70.71014579999999`
  - 실패율: `0.0087565674`
  - `opcounters.update` delta: `6`
- 해석
  - 1분 동안 2,243개 요청 기준으로 MongoDB update가 낮게 수집되어 배치 반영 구조의 쓰기 억제 효과가 유지됨

## 실험 05 — Redis Pipeline(목록 조회 N+1 완화)

- 핵심 의도: 목록 조회 시 Redis 요청 패턴과 응답 p95 개선 정량화
- 실행 스크립트: `./scripts/run-exp05-redis-pipeline.sh`
- 핵심 산출물
  - 목록 조회 p95(둘 다)
  - redis commandstats의 `mget`, `setex` 호출 수
  - 실패율 및 개선률
- 실행 조건
  - `K6_VUS=30`, `K6_DURATION=1m`, `K6_SCENARIO=list_profile`
  - `BASE_URL_A=http://host.docker.internal:8080`
  - `BASE_URL_B=http://host.docker.internal:8080`
  - `LIST_USE_PIPELINE_A=true`, `LIST_USE_PIPELINE_B=false`로 쿼리파라미터만 분리
- 측정값
  - A: p95 `150.40994825`, 실패율 `0.0114220445`, mget `12436`, setex `7`
  - B: p95 `142.60529610`, 실패율 `0.0114220445`, mget `12437`, setex `7`
  - `usePipeline=false`가 `5.19%` 빠름(B가 A 대비)
- 해석
  - 실패율은 동일 범위이나, 현재 환경에서는 pipeline 분기 간 성능 차이가 작고 오히려 파이프라인 미사용이 빠름
  - redis commandstats 수치가 거의 동일해 Redis 호출 수 절감보다 응답분산 요인(네트워크, 연결 설정, 애플리케이션 레이턴시) 추가분해 필요

## PR 반영 메시지 포인트
- Next-Key Lock 실험은 `02/04/06`을 제외한 상태에서 핵심 우선 과제로 재정의됨
- `02`, `04`, `06`은 실행군에서 제외(실패한 재현성과 조건 정합성 이슈로 별도 보류)

## 운영 정책
- Next-Key Lock 실험에서 동시 탈퇴 동시성은 환경변수로 조정 가능 (`NEXTKEY_WITHDRAW_CONCURRENCIES`)
- `run-all.sh` 기본 실행군은 `RUN_EXPERIMENTS=01,03,05`
- 필요시 `run-all.sh`에 `RUN_EXPERIMENTS=02,04,06`를 명시해 별도 재실행 가능
