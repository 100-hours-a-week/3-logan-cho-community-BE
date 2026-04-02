# CloudFront Private Content Benchmark

이 디렉토리는 CloudFront signed cookie, CloudFront signed URL, S3 pre-signed URL 경로를 국내 2지점에서 비교하기 위한 독립 실험 환경이다. 모든 산출물은 이 디렉토리 하위에만 생성된다.

상세 설계 문서는 [experiment-design.md](/home/cho/projects/3-logan-cho-community-BE/test/cf-private-content-benchmark/docs/experiment-design.md), 실행 개요는 [experiment-plan.md](/home/cho/projects/3-logan-cho-community-BE/test/cf-private-content-benchmark/docs/experiment-plan.md), 결과 스키마는 [result-schema.md](/home/cho/projects/3-logan-cho-community-BE/test/cf-private-content-benchmark/docs/result-schema.md)에 정리했다.
로컬 실험 결과 정리 문서는 [local-benchmark-results-2026-04-02.md](/home/cho/projects/3-logan-cho-community-BE/test/cf-private-content-benchmark/docs/local-benchmark-results-2026-04-02.md) 에 있다.

## 전제

- Azure VM 생성은 Terraform으로 관리한다.
- 로컬 PC는 Terraform 관리 대상이 아니다.
- 로컬은 이미 존재하는 실행 위치이므로 스크립트만 제공한다.
- 실제 측정은 `curl -w`로 수행하고, Node.js는 실험 매트릭스 생성, 실행 순서 제어, CSV 저장, 요약 생성에 사용한다.
- signed cookie는 Node.js bootstrap 서버가 쿠키를 발급하고, runner가 그 응답으로 임시 cookie jar를 만든 뒤 asset fetch를 측정한다.

`curl`을 쓰는 이유는 DNS, connect, TLS, TTFB, total time을 명확하게 분리 수집할 수 있기 때문이다.

## 1. Azure CLI 로그인

```bash
az login
az account show
```

필요하면 구독을 고정한다.

```bash
az account set --subscription "<SUBSCRIPTION_ID_OR_NAME>"
```

## 2. 내 공인 IP 확인 후 SSH 허용 CIDR 작성

예시:

```bash
curl -4 https://ifconfig.me
```

출력된 IP가 `198.51.100.24`라면 `terraform.tfvars`에는 `198.51.100.24/32`로 넣는다.

## 3. tfvars 작성

예시 파일을 복사해서 실제 값을 채운다.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

최소 수정 항목:

- `resource_group_name`
- `admin_username`
- `admin_ssh_key_path`
- `allowed_ssh_cidrs`

`terraform.tfvars.example`의 `admin_ssh_key_path`는 예시값이다. 실제 환경의 SSH public key 경로로 바꿔야 한다.

## 4. Terraform 실행

초기화:

```bash
make init
```

플랜:

```bash
make plan
```

적용:

```bash
make apply
```

삭제:

```bash
make destroy
```

직접 실행 예시:

```bash
cd terraform
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
terraform destroy -var-file=terraform.tfvars
```

### 실험용 AWS 스택 생성

현재 Terraform 루트는 로컬 benchmark용 실험 스택 생성 흐름을 포함한다.

- S3 private bucket
- CloudFront distribution
- CloudFront public key / key group
- CloudFront OAC
- 실험용 small / medium / large object 업로드
- 로컬 bootstrap 서버가 사용할 private key PEM 파일 생성

실행:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

필요 권한 예시:

- `s3:CreateBucket`
- `s3:PutBucketPolicy`
- `s3:PutBucketPublicAccessBlock`
- `s3:PutBucketVersioning`
- `s3:PutObject`
- `cloudfront:CreatePublicKey`
- `cloudfront:CreateKeyGroup`
- `cloudfront:CreateOriginAccessControl`
- `cloudfront:CreateCachePolicy`
- `cloudfront:CreateDistribution`

권한이 없으면 실험용 스택 생성이 실패하고 benchmark config 자동 생성도 진행되지 않는다.

## 5. VM 접속 방법

```bash
make ssh
```

또는:

```bash
cd terraform
terraform output -raw ssh_command
```

## 6. benchmark config 작성

예시 config를 복사하고 실제 URL, cookie, object set으로 채운다.

```bash
cd ..
cp configs/benchmark.config.example.json configs/benchmark.config.json
```

중요:

- `miss`는 iteration마다 다른 object가 필요하다.
- `hit`는 priming 후 같은 object를 반복 호출한다.
- `cf_signed_cookie`는 `bootstrap`, `cookieHeader`, `cookieFile` 세 가지 방식을 지원한다.
- URL 전체는 raw CSV에 저장되지 않고 `url_label`만 남는다.

### signed cookie bootstrap 서버 설정

로컬에서 signed cookie를 발급하려면 CloudFront key pair와 private key가 필요하다.

예시:

```bash
npm run cookie-bootstrap:server -- \
  --host 127.0.0.1 \
  --port 3100 \
  --distribution-domain d111111abcdef8.cloudfront.net \
  --key-pair-id K2JCJMDEHXQW5F \
  --private-key-file ./secrets/cloudfront-private-key.pem \
  --cookie-domain d111111abcdef8.cloudfront.net
```

헬스체크:

```bash
curl http://127.0.0.1:3100/health
```

runner는 config의 `cf_signed_cookie[].bootstrap.url`을 보고 bootstrap 서버를 호출한다.

### Terraform output 기반 benchmark config 생성

실험용 AWS 스택 apply 후:

```bash
make generate-config
```

또는:

```bash
node scripts/generate-benchmark-config.js \
  --terraform-dir terraform \
  --output configs/benchmark.config.json
```

이 스크립트는 Terraform output에서 다음을 읽어 실사용 config를 만든다.

- S3 bucket name
- CloudFront domain
- generated private key PEM path
- CloudFront public key id
- object manifest

## 7. npm 설치

```bash
npm install
```

이 프로젝트는 외부 의존성이 거의 없지만, 동일한 실행 절차를 유지하기 위해 `npm install`을 문서화한다.

## 8. 로컬 실험 실행 예시

전체 실행:

```bash
make run-local CONFIG=./configs/benchmark.config.json
```

직접 실행:

```bash
node scripts/run-local-benchmark.js --config configs/benchmark.config.json
```

miss만 실행:

```bash
node scripts/run-local-benchmark.js --config configs/benchmark.config.json --phase miss
```

hit만 실행:

```bash
node scripts/run-local-benchmark.js --config configs/benchmark.config.json --phase hit
```

signed cookie bootstrap 서버와 함께 실행 예시:

```bash
npm run cookie-bootstrap:server -- \
  --host 127.0.0.1 \
  --port 3100 \
  --distribution-domain d111111abcdef8.cloudfront.net \
  --key-pair-id K2JCJMDEHXQW5F \
  --private-key-file ./secrets/cloudfront-private-key.pem
```

다른 터미널에서:

```bash
node scripts/run-local-benchmark.js --config configs/benchmark.config.json --phase miss
node scripts/run-local-benchmark.js --config configs/benchmark.config.json --phase hit
```

## 9. 원격 실험 실행 예시

원격 VM으로 실험 디렉토리를 복사하고 실행:

```bash
make run-remote REMOTE_HOST=azureuser@<VM_PUBLIC_IP> CONFIG=./configs/benchmark.config.json
```

직접 실행:

```bash
scp -r . azureuser@<VM_PUBLIC_IP>:~/cf-private-content-benchmark
ssh azureuser@<VM_PUBLIC_IP> "cd ~/cf-private-content-benchmark && npm install && node scripts/run-remote-benchmark.js --config configs/benchmark.config.json"
```

## 10. 결과 fetch 예시

```bash
make fetch-results REMOTE_HOST=azureuser@<VM_PUBLIC_IP>
```

또는:

```bash
bash scripts/collect-results.sh azureuser@<VM_PUBLIC_IP> ~/cf-private-content-benchmark
```

원격 결과는 `results/remote/<timestamp>/` 아래로 정리된다.

## 11. summary 생성 예시

```bash
make summarize
```

또는:

```bash
node scripts/summarize-results.js --raw-dir results/raw --summary-dir results/summary
```

## 12. 권장 실행 순서

1. `miss` 배치를 로컬과 원격에서 각각 실행
2. `hit` 배치를 로컬과 원격에서 각각 실행
3. 원격 결과 fetch
4. summary 생성

이 순서를 권장하는 이유는 `hit`와 `miss`를 절대 같은 평균 집합으로 섞지 않기 위해서다.

## 반드시 지켜야 할 주의사항

- `hit`와 `miss` 결과를 절대 섞지 말 것
- `miss`는 fresh object를 사용해야 할 것
- `hit`는 priming 요청을 본 측정 평균에서 제외할 것
- signed cookie는 bootstrap 단계와 asset fetch 단계를 분리 해석할 것
- signed URL은 query string이 cache key에 포함되는지 반드시 확인할 것

`cf_signed_cookie`의 raw CSV에는 `measurement_stage=bootstrap`와 `measurement_stage=asset_fetch`가 별도로 기록된다.

`miss` 실험에 fresh object가 필요한 이유는 같은 URL 반복 호출 시 첫 요청 이후 hit로 바뀌어 miss 평균이 오염되기 때문이다.

## 파일 배치 원칙

- 로컬은 Terraform 대상이 아니고 스크립트 대상이다.
- Azure VM만 Terraform 관리 대상이다.
- 실험 코드, 문서, 설정, 결과는 모두 이 디렉토리 하위에만 저장된다.
