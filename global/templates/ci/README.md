# CI/CD 템플릿 (cicd-harness 전용)

`cicd-harness`가 `CICD_BOOTSTRAP` 이슈를 처리할 때 참조하는 CI/CD 워크플로 템플릿 모음.
즉석 생성 대신 **검증된 템플릿을 복사**해 품질 편차와 누락을 없앤다.

## 템플릿 선택 규칙 (빌드 파일 기준)

| 감지 파일 | 템플릿 | 산출 위치 |
|---|---|---|
| `Gemfile` | `rails.yml` | `.github/workflows/ci.yml` |
| `package.json` | `nextjs.yml` | `.github/workflows/ci.yml` |
| `pyproject.toml` / `requirements.txt` | `python.yml` | `.github/workflows/ci.yml` |
| `go.mod` | `go.yml` | `.github/workflows/ci.yml` |
| (없음, doc only) | 생성 안 함 — result에 `cd_skipped` 기록 |

## CD(배포) 스켈레톤 — 배포 흔적 있을 때만

| 감지 | 템플릿 | 산출 위치 |
|---|---|---|
| `config/deploy.yml` (Kamal) | `deploy-kamal.yml` | `.github/workflows/deploy.yml` |

## 절대 규칙 (cicd-harness.md와 동일)

1. **존재하지 않는 명령을 넣지 않는다.** 모든 템플릿은 `--if-present` / 존재 검사 가드를 내장 → CI 처음부터 빨강 방지.
2. **git push 금지.** 파일 생성/커밋까지만. 원격 반영은 대표님 확인.
3. **이미 워크플로가 있으면 덮어쓰지 않는다.**
4. **시크릿 값을 채우지 않는다.** `${{ secrets.X }}` 플레이스홀더만. 실제 값은 대표님이 repo Secrets에 등록(T2 SECURITY).
5. CD는 기본 **수동 트리거(`workflow_dispatch`)**. 자동 배포 전환은 대표님 명시 지시.

## 배포 게이트 권장 패턴

`deploy.yml`이 `ci.yml`의 green 이후에만 돌게 하려면 `workflow_run` 트리거 또는 `needs`로 연결.
기본 스켈레톤은 수동 트리거이므로, 자동화 전환 시 이 게이트를 함께 건다.
