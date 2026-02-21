# Codex 세션에서 gh로 Issue/PR 직접 생성하기

`bin/codex-gh` 런처는 gh 인증 토큰을 자동 주입하고 Codex를 실행한다.

## 1) 1회 준비
```bash
gh auth login -h github.com
```

권장 토큰 권한(Fine-grained PAT):
- `Metadata: Read`
- `Contents: Read and write`
- `Pull requests: Read and write`
- `Issues: Read and write`

## 2) 기본 실행
```bash
./bin/codex-gh
```

동작:
- `gh auth token`으로 `GH_TOKEN` 확보
- `GITHUB_TOKEN` 자동 동기화
- `gh auth status` 및 repo 권한 preflight 확인
- Codex 실행 (`-a on-request`, `-s workspace-write`)

## 3) 옵션
```bash
./bin/codex-gh -C /path/to/repo
./bin/codex-gh -R owner/repo
./bin/codex-gh --skip-preflight
```

## 4) 주의사항
- 토큰 값은 출력하지 않는다.
- repo를 지정하지 않으면 현재 작업 디렉터리의 `remote.origin.url`에서 자동 감지한다.

## 5) 실패 시 확인
- `GH_TOKEN이 비어 있다`:
  `gh auth login -h github.com` 재실행
- `Resource not accessible by integration`:
  토큰 권한/레포 권한 확인
