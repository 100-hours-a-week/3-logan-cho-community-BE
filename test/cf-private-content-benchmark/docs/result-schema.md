# Result Schema

## Raw CSV

파일 위치:

- `results/raw/raw-<location>-<phase>-<timestamp>.csv`
- 원격 실행 시 hostname이 파일명에 추가될 수 있다.

컬럼 설명:

- `run_id`: 한 번의 실행 배치를 식별하는 ID
- `timestamp`: 개별 요청 측정 시각
- `location`: `local_gyeonggi` 또는 `azure_busan`
- `hostname`: 측정을 수행한 호스트 이름
- `cache_phase`: `miss` 또는 `hit`
- `object_size_case`: `small`, `medium`, `large`
- `delivery_type`: `s3_presigned`, `cf_signed_url`, `cf_signed_cookie`
- `object_id`: miss 실험에서 fresh object를 식별하는 값
- `iteration`: 반복 번호. hit priming은 `0`
- `primed`: priming 요청 여부. `true`면 본 측정 평균에서 제외해야 한다
- `http_code`: curl이 관측한 HTTP status code
- `time_namelookup`: DNS lookup 시간
- `time_connect`: TCP connect 시간
- `time_appconnect`: TLS handshake 완료 시간
- `time_starttransfer`: TTFB
- `time_total`: 전체 요청 시간
- `size_download`: 다운로드된 바이트 수
- `remote_ip`: 응답한 원격 IP
- `url_label`: 민감 정보가 없는 URL 식별 라벨

## Summary CSV / JSON

파일 위치:

- `results/summary/summary-all-<timestamp>.csv`
- `results/summary/summary-all-<timestamp>.json`
- `results/summary/summary-miss-<timestamp>.csv`
- `results/summary/summary-hit-<timestamp>.csv`

컬럼 설명:

- `location`
- `cache_phase`
- `object_size_case`
- `delivery_type`
- `count`: priming 제외 후 해당 그룹에 포함된 row 수
- `avg_time_namelookup`, `p50_time_namelookup`, `p95_time_namelookup`
- `avg_time_connect`, `p50_time_connect`, `p95_time_connect`
- `avg_time_appconnect`, `p50_time_appconnect`, `p95_time_appconnect`
- `avg_time_starttransfer`, `p50_time_starttransfer`, `p95_time_starttransfer`
- `avg_time_total`, `p50_time_total`, `p95_time_total`

## 나중에 직접 계산할 때 기준이 되는 컬럼

비용 또는 절감률 계산은 raw CSV 기준으로 직접 수행하는 것이 가장 안전하다.

- 전송량 추정:
  `size_download`를 `location × cache_phase × object_size_case × delivery_type` 기준으로 합산
- 응답시간 평균 비교:
  `primed=false` 조건을 유지한 뒤 `time_starttransfer` 또는 `time_total` 평균 계산
- 퍼센타일 비교:
  같은 4차원 그룹 안에서 `p50`, `p95` 계산
- hit 효율 비교:
  같은 `location`, `object_size_case`, `delivery_type`에서 `cache_phase=miss`와 `cache_phase=hit`를 따로 비교

주의:

- `hit`와 `miss`는 절대 하나의 평균 집합으로 합치지 않는다.
- `cf_signed_cookie`의 bootstrap 시간은 이 CSV에 자동 포함되지 않는다.
- `cf_signed_url`은 query string이 cache key에 반영되는 정책인지 먼저 확인해야 한다.
