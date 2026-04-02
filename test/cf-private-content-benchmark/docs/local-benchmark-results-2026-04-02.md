# Local Benchmark Results 2026-04-02

## 범위

이 문서는 `local_gyeonggi` 기준으로 2026-04-02에 수행한 실험 결과를 정리한다.

- 실험 대상:
  - `s3_presigned`
  - `cf_signed_url`
  - `cf_signed_cookie`
- cache phase:
  - `miss`
  - `hit`
- object size:
  - `small`
  - `medium`
  - `large`
- location:
  - `local_gyeonggi`

중요:

- 이 결과는 실험용 Terraform AWS 스택으로 생성한 S3 + CloudFront private content 환경 기준이다.
- `azure_busan` 측정은 아직 수행하지 않았다.
- signed cookie는 bootstrap과 asset fetch를 분리 기록했다.

## 사용한 실험 스택

- S3 bucket: `cf-private-benchmark-3txmenu9`
- CloudFront distribution id: `E1VLOG17F39ILT`
- CloudFront domain: `dmk4kd0076dd8.cloudfront.net`
- CloudFront public key id: `K19P8ZH78ESU96`

## 생성된 결과 파일

Raw:

- [raw-local_gyeonggi-miss-2026-04-02T13-44-22-527Z.csv](/home/cho/projects/3-logan-cho-community-BE/test/cf-private-content-benchmark/results/raw/raw-local_gyeonggi-miss-2026-04-02T13-44-22-527Z.csv)
- [raw-local_gyeonggi-hit-2026-04-02T13-44-58-865Z.csv](/home/cho/projects/3-logan-cho-community-BE/test/cf-private-content-benchmark/results/raw/raw-local_gyeonggi-hit-2026-04-02T13-44-58-865Z.csv)

Summary:

- [summary-miss-2026-04-02T13-45-08-133Z.csv](/home/cho/projects/3-logan-cho-community-BE/test/cf-private-content-benchmark/results/summary/summary-miss-2026-04-02T13-45-08-133Z.csv)
- [summary-hit-2026-04-02T13-45-08-134Z.csv](/home/cho/projects/3-logan-cho-community-BE/test/cf-private-content-benchmark/results/summary/summary-hit-2026-04-02T13-45-08-134Z.csv)
- [summary-bootstrap-2026-04-02T13-45-08-134Z.csv](/home/cho/projects/3-logan-cho-community-BE/test/cf-private-content-benchmark/results/summary/summary-bootstrap-2026-04-02T13-45-08-134Z.csv)

Row count:

- miss raw: `240` data rows
- hit raw: `282` data rows

설명:

- miss:
  - `9 groups × 20 iterations = 180 asset_fetch rows`
  - `3 cf_signed_cookie groups × 20 iterations = 60 bootstrap rows`
- hit:
  - `9 groups × 30 iterations = 270 asset_fetch rows`
  - `3 cf_signed_cookie groups × 1 bootstrap row = 3 bootstrap rows`
  - `9 groups × 1 priming row = 9 primed asset_fetch rows`

## 요약 결과

### Miss, avg_time_total

| object size | s3_presigned | cf_signed_url | cf_signed_cookie |
|---|---:|---:|---:|
| small | 0.143583 | 0.119291 | 0.140620 |
| medium | 0.201723 | 0.296116 | 0.112071 |
| large | 0.265984 | 0.191382 | 0.163754 |

### Hit, avg_time_total

| object size | s3_presigned | cf_signed_url | cf_signed_cookie |
|---|---:|---:|---:|
| small | 0.107739 | 0.061207 | 0.090551 |
| medium | 0.128577 | 0.077738 | 0.115589 |
| large | 0.182188 | 0.162751 | 0.139193 |

### Bootstrap, avg_time_total

| phase | object size | cf_signed_cookie bootstrap |
|---|---|---:|
| miss | small | 0.004970 |
| miss | medium | 0.004150 |
| miss | large | 0.005281 |
| hit | small | 0.003021 |
| hit | medium | 0.002665 |
| hit | large | 0.002724 |

## 핵심 관찰

### 1. Hit에서는 CloudFront 경로가 전반적으로 우세했다

모든 size case에서 `s3_presigned`보다 CloudFront 경로가 낮은 `avg_time_total`을 보였다.

- small hit:
  - `cf_signed_url 0.061207`
  - `cf_signed_cookie 0.090551`
  - `s3_presigned 0.107739`
- medium hit:
  - `cf_signed_url 0.077738`
  - `cf_signed_cookie 0.115589`
  - `s3_presigned 0.128577`
- large hit:
  - `cf_signed_cookie 0.139193`
  - `cf_signed_url 0.162751`
  - `s3_presigned 0.182188`

### 2. Miss에서도 CloudFront가 더 빠른 조합이 다수 관측됐다

특히 `large miss`에서 CloudFront 경로가 S3 direct보다 유의미하게 낮았다.

- large miss:
  - `cf_signed_cookie 0.163754`
  - `cf_signed_url 0.191382`
  - `s3_presigned 0.265984`

이 결과는 이상치라고 단정할 수 없다. `client -> CloudFront edge`와 `edge -> S3`의 결합 경로가 `client -> S3 regional endpoint`보다 유리할 수 있기 때문이다. CloudFront miss는 단순히 public internet hop 하나가 늘어난 구조로 보면 안 된다.

### 3. Medium miss에서는 cf_signed_url이 불안정했다

`medium miss`에서 `cf_signed_url avg_time_total`이 `0.296116`으로 가장 높았고, `p95_time_total`도 `0.319271`로 튀었다. 같은 case에서 `cf_signed_cookie`는 `0.112071`이었다.

이 구간은 signed URL 자체의 구조적 열세라기보다 측정 시점의 network variance 또는 개별 object 요청 편차 가능성이 있다. 특히 이번 실험용 스택은 query string을 cache key에 포함하지 않도록 CloudFront cache policy를 구성했기 때문에, signed URL이 캐시 정책 때문에 반드시 불리한 상태는 아니었다.

### 4. Bootstrap 비용은 asset fetch와 분리했을 때 작았다

`cf_signed_cookie` bootstrap은 로컬 기준 대략 `2.7ms ~ 5.3ms` 수준이었다. 따라서 이번 실험에서는 asset fetch 성능을 해석할 때 bootstrap을 합산하지 않는 것이 타당하다.

## 해석

### 왜 miss인데도 CloudFront가 더 빠를 수 있는가

가능한 설명은 다음과 같다.

- `local -> CloudFront edge`가 `local -> S3`보다 더 짧거나 안정적인 경로일 수 있다
- `edge -> S3`는 AWS 내부 네트워크 구간이므로 공용 인터넷보다 유리할 수 있다
- 이번 실험용 스택은 정적 binary object + query string 미포함 cache policy로 CloudFront에 유리한 조건이다

즉, `CloudFront miss`를 단순히 "홉이 하나 더 있는 direct S3"로 보면 해석이 틀어진다.

### 그렇다고 일반화할 수는 없다

이 결과는 아래 범위에서만 유효하다.

- local_gyeonggi 1지점
- 2026-04-02 측정 시점
- Terraform으로 만든 실험용 S3 + CloudFront stack
- `small/medium/large` 3개 바이너리 크기 케이스

특히 Azure Busan이 아직 없으므로 “국내 2지점 대표 결과”라고 부르기에는 아직 이르다.

## 현재 결론

로컬 기준으로는 다음 가설이 지지됐다.

- `cache_phase=hit`에서 CloudFront 경로가 `s3_presigned`보다 빠를 가능성이 높다
- `cache_phase=miss`에서도 CloudFront 경로가 충분히 경쟁력 있을 수 있다
- signed cookie bootstrap은 asset fetch와 분리 기록하는 것이 맞다

아직 남은 검증:

- `azure_busan` 동일 매트릭스 수행
- 같은 경향이 원격 측정점에서도 유지되는지 확인
