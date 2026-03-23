## 근본 목적
`post_likes`에서 `12B post_id` 기준으로 복합 PK와 단일 PK 전략을 순수하게 비교하고, 공통 secondary 개수와 데이터 양이 증가할 때 손익분기점이 어디서 생기는지 정량적으로 기록한다.

## 비목적
이번 보고서는 soft delete, feed covering, 서비스 최종 쿼리 설계 우열을 결론내리기 위한 것이 아니다. Mongo `ObjectId`에 가까운 `BINARY(12)` 기준에서 PK 전략 자체의 저장 구조와 exact lookup 비용만 본다.

## 실험 구성
- 기준선 `#67`
  - `C`: `PRIMARY KEY (post_id, member_id)`
  - `S`: `PRIMARY KEY (post_like_id)`, `UNIQUE KEY uk_post_member (post_id, member_id)`
  - row count: `1,000,000`
  - dist: `uniform`, `skew`
  - workload: exact lookup probe `50,000~100,000`개 재생
- 손익분기 `#68`
  - 같은 `C/S` 스키마
  - 공통 secondary 레벨: `L0~L5`
  - row count: `100,000`, `300,000`, `1,000,000`
  - dist: `uniform`, `skew`

## 어떻게 측정했는가
- 저장 구조
  - `information_schema.tables`에서 `data_length`, `index_length`를 읽어 총 크기를 확인했다.
  - `mysql.innodb_table_stats`의 `clustered_index_size`, `sum_of_other_index_sizes`를 이용해 clustered 페이지와 other index 페이지를 분리했다.
- 밀집도
  - `row_count / clustered_pages`
  - `row_count / other_pages`
  - 형태로 페이지당 row 수를 계산했다.
- exact lookup
  - `bench_probe_keys`에 probe key를 고정 생성한 뒤 아래 lookup을 반복했다.
  - `SELECT 1 FROM post_likes_case WHERE post_id = ? AND member_id = ? LIMIT 1`
  - 실행 전후 `Innodb_buffer_pool_reads`, `Innodb_buffer_pool_read_requests`, `Innodb_data_reads`를 읽어 평균 delta를 구했다.
- break-even
  - `C_total = data_mb + index_mb`
  - `S_total = data_mb + index_mb`
  - 를 레벨별/row count별로 비교해 `S_total - C_total <= 0`이 되는 첫 지점을 손익분기점으로 기록했다.

## 기준선 결과
출처:
- `test/post-likes-benchmark/results/pk_pure_baseline_12b/summary.tsv`
- `test/post-likes-benchmark/results/pk_pure_baseline_12b/*_table_stats.tsv`

### 1) 저장 구조
- `uniform`
  - `C` 총 크기: `82.734MB`
  - `S` 총 크기: `113.235MB`
  - 차이: `S +30.501MB`
  - `C clustered`: `82.734MB`
  - `S clustered`: `56.594MB`
  - `S uk_post_member`: `56.641MB`
- `skew`
  - `C` 총 크기: `77.703MB`
  - `S` 총 크기: `112.235MB`
  - 차이: `S +34.532MB`
  - `C clustered`: `77.703MB`
  - `S clustered`: `56.594MB`
  - `S uk_post_member`: `55.641MB`

### 2) 밀집도
- `uniform`
  - `C primary rows/page`: `188.857`
  - `S primary rows/page`: `276.091`
  - `S uk_post_member rows/page`: `275.862`
- `skew`
  - `C primary rows/page`: `201.086`
  - `S primary rows/page`: `276.091`
  - `S uk_post_member rows/page`: `280.820`

### 3) exact lookup 비용
- `uniform`
  - `C lookup avg`: `233.897ms`
  - `S lookup avg`: `156.139ms`
  - `C buffer_pool_reads avg`: `3071.667`
  - `S buffer_pool_reads avg`: `1483.000`
- `skew`
  - `C lookup avg`: `238.661ms`
  - `S lookup avg`: `159.275ms`
  - `C buffer_pool_reads avg`: `2785.667`
  - `S buffer_pool_reads avg`: `1400.000`

## 해석
- `12B post_id` 기준 `L0`에서는 `S`가 항상 더 크다.
- 이유는 `S`가 시작부터 `PRIMARY(id) + uk_post_member(post_id, member_id)`라는 고정비를 갖기 때문이다.
- 하지만 clustered 관점에서는 `C`가 더 크고, exact lookup I/O도 `C`가 더 무겁다.
- 즉 `S`는 시작 비용이 크지만, lookup 경로에서 참조하는 PK는 더 짧고 clustered 밀집도도 더 좋다.
- 반대로 `C`는 인덱스 수가 적은 초반에는 총량이 작지만, 공통 secondary가 늘수록 긴 PK `(post_id, member_id)`가 각 secondary 엔트리에 반복 복제된다.
- 따라서 break-even은 `S의 고정비`와 `C의 secondary 누적비`가 만나는 지점으로 해석해야 한다.

## break-even 결과
출처:
- `test/post-likes-benchmark/results/pk_break_even_12b/size_matrix.tsv`
- `test/post-likes-benchmark/results/pk_break_even_12b/break_even_by_secondary.tsv`
- `test/post-likes-benchmark/results/pk_break_even_12b/break_even_by_row_count.tsv`

### secondary-count break-even
- `100,000`
  - `uniform`: 없음
  - `skew`: 없음
- `300,000`
  - `uniform`: 없음
  - `skew`: 없음
- `1,000,000`
  - `uniform`: `L2`
  - `skew`: `L5`

### row-count break-even
- `uniform`
  - `L0`: 없음
  - `L1`: 없음
  - `L2`: `1,000,000`
  - `L3`: `1,000,000`
  - `L4`: `1,000,000`
  - `L5`: `1,000,000`
- `skew`
  - `L0~L4`: 없음
  - `L5`: `1,000,000`

### 대표 수치
- `1,000,000 / uniform`
  - `L0`: `C 102.766MB`, `S 114.250MB`, `delta +11.484MB`
  - `L1`: `C 128.344MB`, `S 135.813MB`, `delta +7.469MB`
  - `L2`: `C 160.954MB`, `S 157.375MB`, `delta -3.579MB`
  - `L5`: `C 283.829MB`, `S 272.219MB`, `delta -11.610MB`
- `1,000,000 / skew`
  - `L0`: `C 89.734MB`, `S 111.250MB`, `delta +21.516MB`
  - `L4`: `C 235.187MB`, `S 237.625MB`, `delta +2.438MB`
  - `L5`: `C 267.797MB`, `S 266.219MB`, `delta -1.578MB`

## 결론
- `12B post_id` 기준에서 단일 PK 전략은 작은 스케일에서는 고정비가 더 크다.
- `1,000,000 row`까지 올라가고 공통 secondary가 충분히 많아지면 `S`가 전체 저장 크기에서 역전한다.
- 역전 시점은 분포에 따라 달랐다.
  - `uniform`: 공통 secondary `2개`부터
  - `skew`: 공통 secondary `5개`부터
- `uniform`이 더 빨리 역전한 이유는 row가 post_id 전반에 더 넓게 퍼져 `C`의 clustered/pages 비용과 공통 secondary 누적 비용이 더 크게 드러났기 때문이다.
- `skew`가 늦게 역전한 이유는 hot post 집중으로 인해 `C`의 clustered/pages 이점이 일부 유지되고, `S`의 고정비를 상쇄하려면 더 많은 secondary가 필요했기 때문이다.
- 따라서 `12B` 환경에서는 “단일 PK가 항상 유리하다”도 아니고 “복합 PK가 항상 유리하다”도 아니다. 데이터 양과 공통 secondary 개수에 따라 손익분기점이 실제로 존재한다.
