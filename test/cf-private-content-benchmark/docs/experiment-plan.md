# CloudFront Private Content Benchmark Experiment Plan

## 목적

이 실험은 국내 2지점에서 아래 3개 전달 경로의 성능을 정량 비교하기 위한 것이다.

- `s3_presigned`
- `cf_signed_url`
- `cf_signed_cookie`

비용 계산 자체를 자동으로 하려는 목적은 아니다. 대신 나중에 직접 비용, 전송량, 절감률을 계산할 수 있도록 오염되지 않은 raw 측정 결과와 phase 분리된 요약 결과를 남기는 것이 목적이다.

## 왜 hit 와 miss 평균을 분리해야 하는가

`cache miss`와 `cache hit`는 네트워크 경로와 원본 접근 여부가 다르다. 두 값을 섞으면 CDN 캐시 효과가 있는지 없는지 판단할 수 없다. 따라서 이 실험에서는 `cache_phase=miss`와 `cache_phase=hit`를 완전히 다른 집합으로 취급한다.

## 왜 miss 는 iteration 마다 fresh object 여야 하는가

같은 URL을 반복 호출하면 첫 요청만 miss이고 이후 요청은 hit로 전환될 수 있다. 그러면 miss 평균이 오염된다. 따라서 `miss` 실험은 iteration마다 다른 object key 또는 다른 cache key를 가진 요청으로 구성해야 한다. 이 하네스는 `miss` 그룹에서 iteration 수보다 충분히 많은 서로 다른 entry가 없으면 실행을 중단한다.

## 왜 signed cookie 는 bootstrap 단계와 asset fetch 단계를 분리해야 하는가

Signed cookie는 일반적으로 다음 2단계로 나뉜다.

1. bootstrap: 애플리케이션이 쿠키를 발급하거나 세팅하는 단계
2. asset fetch: 브라우저나 클라이언트가 실제 private asset을 가져오는 단계

이 둘을 합치면 CloudFront asset fetch 자체의 성능과 인증 부트스트랩 비용이 뒤섞인다. 이번 하네스는 Node.js bootstrap 서버 호출과 asset fetch를 서로 다른 row로 기록한다. raw CSV에서는 `measurement_stage=bootstrap`와 `measurement_stage=asset_fetch`로 분리되고, asset fetch summary에서는 bootstrap row를 합치지 않는다.

## 왜 signed URL 은 cache key 설계 영향을 강하게 받는가

CloudFront가 query string을 cache key에 포함하도록 설정되어 있으면 signed URL의 서명 파라미터가 캐시를 분산시킬 수 있다. 그러면 같은 object여도 사실상 캐시 효율이 낮아질 수 있다. 따라서 signed URL 결과는 CloudFront cache policy와 query string forwarding 정책을 함께 해석해야 한다.

## 실험 매트릭스

모든 결과는 아래 4차원 키로 분리 저장하고 요약한다.

| location | cache_phase | object_size_case | delivery_type |
|---|---|---|---|
| local_gyeonggi | miss | small | s3_presigned |
| local_gyeonggi | miss | small | cf_signed_url |
| local_gyeonggi | miss | small | cf_signed_cookie |
| local_gyeonggi | miss | medium | ... |
| local_gyeonggi | miss | large | ... |
| local_gyeonggi | hit | small | ... |
| local_gyeonggi | hit | medium | ... |
| local_gyeonggi | hit | large | ... |
| azure_busan | miss | small | ... |
| azure_busan | miss | medium | ... |
| azure_busan | miss | large | ... |
| azure_busan | hit | small | ... |
| azure_busan | hit | medium | ... |
| azure_busan | hit | large | ... |

실제 요약은 위 조합 전체에 대해 `location × cache_phase × object_size_case × delivery_type` 기준으로 group by 된다.

## 권장 실행 순서

1. config 작성
2. Azure VM 생성
3. 로컬과 Azure Busan에서 `miss` 배치 실행
4. 로컬과 Azure Busan에서 `hit` 배치 실행
5. 결과 수집
6. summary 생성

권장 이유는 `hit`와 `miss`를 같은 시간대에 섞지 않아야 해석이 단순해지기 때문이다. 이 하네스는 각 phase를 별도 파일로 저장한다.

## 실행 배치 원칙

- `miss` 배치는 `miss` 그룹끼리만 라운드로빈한다.
- `hit` 배치는 그룹별 priming 후 `hit` 그룹끼리만 라운드로빈한다.
- priming 요청은 raw CSV에 남기되 `primed=true`로 기록하고 summary 집계에서는 제외한다.

## 결과 해석 방법

- 같은 `location` 안에서 `delivery_type` 비교:
  같은 네트워크 위치에서 전달 방식만 바꿨을 때 TTFB와 total time 차이를 본다.
- 같은 `delivery_type` 안에서 `hit` vs `miss` 비교:
  캐시 유효성이 실제로 있는지 본다.
- 같은 조합에서 `local_gyeonggi` vs `azure_busan` 비교:
  국내 2지점 간 편차를 본다.

평균만 보지 말고 최소 `avg`, `p50`, `p95`를 함께 본다.

## 이번 결과의 한계

- 국내 2지점 대표 실험이다.
- 전 세계 사용자에 대한 일반화 실험이 아니다.
- CloudFront cache policy, origin shield, AWS 리전, S3 위치, Azure VM 스펙에 따라 절대값은 달라질 수 있다.
