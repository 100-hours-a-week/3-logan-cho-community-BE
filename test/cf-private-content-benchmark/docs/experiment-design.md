# CloudFront Private Content Benchmark Detailed Design

## 1. 배경과 문제 정의

이 실험은 private content 전달 방식 3가지를 국내 2지점에서 비교하기 위한 것이다.

- `s3_presigned`
- `cf_signed_url`
- `cf_signed_cookie`

관심사는 단순한 평균 속도 비교가 아니다. 실제 운영 판단에 필요한 질문은 다음과 같다.

1. CloudFront private content 경로가 국내 사용자 관점에서도 cache hit 구간에서 유의미한 이점을 보이는가
2. cache miss 구간에서는 CloudFront 경유 비용이 성능상 어떤 trade-off를 가지는가
3. signed cookie, signed URL, S3 pre-signed URL이 같은 object size 조건에서 어떤 형태로 latency 분포가 달라지는가
4. 경기도 로컬 환경과 Azure Busan 환경에서 경향이 일관적인가

이번 실험은 이 질문에 답할 수 있도록 raw 결과와 phase 분리된 summary를 남기는 데 목적이 있다.

## 2. 무엇을 검증하려는가

### 2.1 1차 검증 질문

- `cache_phase=hit`에서 `cf_signed_url` 또는 `cf_signed_cookie`가 `s3_presigned`보다 `time_starttransfer`와 `time_total`에서 더 낮은 값을 보이는가
- 같은 `delivery_type` 안에서 `miss` 대비 `hit`의 개선 폭이 object size별로 어떻게 달라지는가
- signed cookie와 signed URL의 asset fetch 경로는 CloudFront를 통과하므로 유사한 성능을 보여야 하는데, 실제로는 query string cache key 정책 또는 cookie bootstrap 전략 때문에 차이가 발생하는가

### 2.2 2차 검증 질문

- `small`, `medium`, `large`에서 개선 폭이 동일하지 않은가
- Azure Busan과 local_gyeonggi 간 절대값 차이는 있어도 상대 순위는 유지되는가
- tail latency인 `p95`에서도 같은 결론이 유지되는가

### 2.3 이번 실험에서 의도적으로 제외하는 것

- 전 세계 사용자 일반화
- 비용 계산 자동화
- 브라우저 렌더링 시간
- signed cookie bootstrap API 자체의 end-to-end UX 시간

부트스트랩 시간은 별도 문제이며, 이번 문서는 asset fetch 성능을 깨끗하게 분리 측정하는 설계를 다룬다.

## 3. 실험 가설

### 가설 A

국내 2지점 기준으로 `cache_phase=hit`에서는 CloudFront 경로가 `s3_presigned`보다 낮은 `time_starttransfer`를 보일 가능성이 높다.

### 가설 B

`cache_phase=miss`에서는 CloudFront가 origin fetch를 수행하므로 `s3_presigned`와의 차이가 작거나, 경우에 따라 더 느릴 수 있다.

### 가설 C

Signed URL은 query string이 cache key에 포함되는 정책이라면 cache hit 효율이 저하될 수 있다. 같은 object를 요청해도 서명 query 차이로 edge cache 분산이 발생할 수 있다.

### 가설 D

Signed cookie는 asset fetch 단계만 보면 CloudFront signed URL과 유사한 경향을 보이지만, 실제 서비스 UX는 bootstrap 단계 비용에 따라 달라질 수 있다. 따라서 bootstrap 단계와 asset fetch 단계는 분리 측정해야 한다.

## 4. 독립 변수와 종속 변수

### 4.1 독립 변수

- `location`
  - `local_gyeonggi`
  - `azure_busan`
- `cache_phase`
  - `miss`
  - `hit`
- `object_size_case`
  - `small`
  - `medium`
  - `large`
- `delivery_type`
  - `s3_presigned`
  - `cf_signed_url`
  - `cf_signed_cookie`

### 4.2 종속 변수

- `time_namelookup`
- `time_connect`
- `time_appconnect`
- `time_starttransfer`
- `time_total`
- `size_download`
- `http_code`
- `remote_ip`

주요 판단 지표는 `time_starttransfer`와 `time_total`이다. 나머지는 병목 위치를 해석하기 위한 보조 지표다.

## 5. 통제 변수

실험 비교가 성립하려면 아래를 최대한 통제해야 한다.

- 같은 지역 시간대에 `miss` 배치는 서로 가까운 시점에 수행
- 같은 지역 시간대에 `hit` 배치는 서로 가까운 시점에 수행
- `small`, `medium`, `large`는 delivery type 간 가능한 한 동일하거나 유사한 콘텐츠 성격 유지
- 각 object size case 내에서 파일 타입과 압축 특성을 최대한 유사하게 유지
- 측정 도구는 모든 조건에서 동일하게 `curl -w`
- 결과 저장 포맷은 모두 동일한 CSV schema

## 6. 실험 단위와 표본 정의

이 실험의 최소 샘플 단위는 "단일 HTTP GET 요청 1회"다.

각 요청은 아래 4차원 그룹 중 하나에 속한다.

- `location`
- `cache_phase`
- `object_size_case`
- `delivery_type`

각 그룹은 별도의 표본 집합이다. 따라서 집계도 그룹별로만 수행한다. 어떤 경우에도 `hit`와 `miss`를 합산 평균내지 않는다.

## 7. cache miss 설계

### 7.1 왜 miss 반복 호출이 위험한가

같은 URL을 연속 호출하면 첫 요청 이후 edge 또는 중간 캐시에 의해 hit로 전환될 수 있다. 그러면 miss 평균이 오염되고 CDN 효과를 과장하게 된다.

### 7.2 miss 설계 원칙

- iteration마다 서로 다른 object key 또는 서로 다른 cache key를 사용한다
- 같은 entry를 반복 사용하지 않는다
- 각 miss 그룹은 반복 횟수 이상으로 충분한 fresh object 목록을 가진다

### 7.3 구현 방식

config 파일의 `objectCases.<size>.miss.<delivery_type>`에는 fresh object 목록을 넣는다. 실행기는 miss 배치에서 iteration 번호마다 서로 다른 entry를 사용한다. 엔트리 수가 반복 횟수보다 적으면 실행을 실패시킨다.

## 8. cache hit 설계

### 8.1 hit 정의

같은 object에 대해 edge 또는 경로가 워밍업된 이후의 반복 요청 집합이다.

### 8.2 hit 설계 원칙

- 그룹별 priming 요청 1회 수행
- priming에 사용한 동일 object를 반복 호출
- priming row는 raw에는 남기되 summary 집계에서는 제외

### 8.3 구현 방식

config 파일의 `objectCases.<size>.hit.<delivery_type>`에는 보통 1개 object를 둔다. 실행기는 먼저 priming 요청을 보내고 그 뒤 동일 entry로 정해진 횟수만큼 반복 측정한다.

## 9. signed cookie 경로 설계

Signed cookie는 애플리케이션 또는 별도 bootstrap API가 cookie를 발급하고, 이후 asset 요청에서 cookie가 함께 전송된다.

이번 실험에서 중요한 점은 다음과 같다.

- bootstrap 시간은 asset fetch 자체와 다른 문제다
- cookie 발급 API latency, 세션 생성, 인증 미들웨어 비용을 asset CDN latency와 섞으면 안 된다
- 따라서 이번 측정기는 cookie가 이미 준비된 상태를 전제로 `targetUrl` fetch만 측정한다

향후 필요하면 bootstrap 단계용 CSV를 별도로 추가할 수 있도록 config에 `cookieHeader`, `cookieFile`, `bootstrapLabel` 확장 여지를 두었다.

## 10. signed URL 경로 설계

Signed URL은 query string 기반 인증이 일반적이다. 이때 CloudFront cache policy가 query string을 cache key에 어떻게 반영하는지 반드시 확인해야 한다.

해석 규칙:

- query string 전체가 cache key에 포함되면 cache hit 효율이 저하될 수 있다
- 인증 파라미터를 무시하거나 최소 key만 포함하는 정책이면 signed URL도 높은 캐시 효율을 가질 수 있다

즉, signed URL이 느리게 측정되었다면 원인이 "signed URL이라는 방식 자체"인지, 아니면 "cache policy 설계"인지 분리해서 봐야 한다.

## 11. 위치 설계

이번 실험은 아래 2지점 대표 측정이다.

- `local_gyeonggi`
- `azure_busan`

의미는 다음과 같다.

- `local_gyeonggi`: 실제 개발자 로컬 인터넷 환경의 대표 관측점
- `azure_busan`: Korea South 리전의 클라우드 VM 관측점

이 둘은 국내 대표 관측점일 뿐이며, 모바일 네트워크, 해외 사용자, ISP별 편차를 대변하지 않는다.

## 12. object size 설계

파일 크기는 코드에 하드코딩하지 않고 label 기반으로만 관리한다.

- `small`: 15KB~30KB 수준의 프로필 또는 썸네일 유사 파일
- `medium`: 100KB~300KB 수준
- `large`: 800KB 전후의 상세 이미지 유사 파일

핵심은 절대 바이트값보다 "운영에서 자주 나오는 객체군의 대표 크기"를 비교 단위로 쓰는 것이다.

## 13. 반복 횟수와 실행 순서

기본값 예시는 다음과 같다.

- `miss`: 20회
- `hit`: 30회

권장 실행 순서:

1. local_gyeonggi에서 miss 실행
2. azure_busan에서 miss 실행
3. local_gyeonggi에서 hit 실행
4. azure_busan에서 hit 실행
5. raw 결과 취합
6. summary 생성

동일 phase 안에서는 그룹 간 라운드로빈을 허용하지만, 서로 다른 phase는 같은 배치로 섞지 않는다.

## 14. 수집 방식

수집은 `curl -w`로 수행한다. 이유는 각 지표의 의미가 명확하고 해석 가능성이 높기 때문이다.

- DNS: `time_namelookup`
- TCP: `time_connect`
- TLS: `time_appconnect`
- TTFB: `time_starttransfer`
- End-to-end: `time_total`

Node.js는 다음 역할만 담당한다.

- config 로딩
- 실험 매트릭스 생성
- 배치 실행 순서 제어
- CSV 저장
- summary 계산

## 15. 결과 저장 설계

### raw 결과

raw CSV는 개별 요청 레벨 기록이다. 나중에 직접 통계나 비용 계산을 다시 할 수 있도록 최대한 가공 없이 저장한다.

특히 아래 컬럼이 중요하다.

- `location`
- `cache_phase`
- `object_size_case`
- `delivery_type`
- `object_id`
- `iteration`
- `primed`
- `size_download`

### summary 결과

summary는 아래 키로 group by 한다.

- `location`
- `cache_phase`
- `object_size_case`
- `delivery_type`

각 그룹에 대해 최소 다음을 계산한다.

- `count`
- `avg`, `p50`, `p95` for `time_starttransfer`
- `avg`, `p50`, `p95` for `time_total`

## 16. 데이터 품질 체크

실행 후 아래를 확인해야 한다.

- `http_code`가 기대 상태코드인지
- `size_download`가 object case에 맞는지
- `miss` 그룹에서 `object_id`가 iteration별로 중복되지 않는지
- `hit` summary에 `primed=true` row가 포함되지 않았는지
- `cf_signed_cookie` 요청이 cookie 누락으로 403이 나지 않았는지

## 17. 결과 해석 프레임

### 같은 location 내 delivery type 비교

같은 네트워크 위치에서 어떤 private content 전달 방식이 더 낮은 latency 분포를 가지는지 본다.

### 같은 delivery type 내 hit vs miss 비교

CDN 캐시가 실제로 이익을 주는지 본다. 이 비교가 가장 중요하다.

### 같은 조합 내 location 비교

로컬 환경과 Azure Busan에서 경향성이 같은지 본다. 절대값보다 상대 순위의 일관성을 먼저 본다.

## 18. 성공 조건

이번 실험 설계가 성공했다고 판단하는 기준은 다음과 같다.

- 모든 4차원 그룹이 raw와 summary에서 분리 집계된다
- miss는 fresh object 기반으로만 구성된다
- hit는 priming 제외 후 집계된다
- signed cookie bootstrap과 asset fetch 해석이 문서상 분리된다
- signed URL cache key 위험이 문서와 결과 해석에 반영된다

## 19. 한계와 주의

- 국내 2지점 대표 실험이다
- 시간대, 인터넷 상태, origin 부하, CloudFront edge 선택에 따라 결과가 흔들릴 수 있다
- 실제 사용자 브라우저 재사용 연결, HTTP/2 multiplexing, 서비스 워크플로 전체 시간은 별도 문제다
- 이번 결과만으로 전사 비용 정책을 바로 확정하면 안 되고, raw 결과를 바탕으로 후속 계산이 필요하다

## 20. 최종 산출물

최종적으로 남겨야 하는 산출물은 다음과 같다.

1. Terraform 코드와 실행 문서
2. 로컬/원격 벤치마크 실행기
3. raw CSV 결과
4. summary CSV/JSON 결과
5. 실험 설계 문서
6. 결과 스키마 문서

이 문서는 그중 5번에 해당하며, 나머지 산출물의 해석 기준이 된다.
