# 작업 워크플로우

## 기준 브랜치
- 기능 브랜치는 `develop`에서 생성한다.
- PR base는 `develop`으로 설정한다.

## 최소 명령 예시
```bash
# 1) develop 최신화
git fetch origin -a
git checkout develop
git pull origin develop

# 2) Issue 번호 기반 브랜치 생성
ISSUE_NUMBER=56
SLUG=codex-gh-launcher
git checkout -b feature/${SLUG}-${ISSUE_NUMBER}

# 3) 작업/검증 후 커밋
git add .
git commit -m "chore: update workflow base to develop"

# 4) PR 생성 (base=develop)
git push -u origin feature/${SLUG}-${ISSUE_NUMBER}
gh pr create --base develop --head feature/${SLUG}-${ISSUE_NUMBER} --fill
```
