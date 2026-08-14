# wiki/ — code wiki scaffold templates

GH_Harness `install.sh --with-wiki` 트리거 시 현재 프로젝트에 복사되는 템플릿 모음.

## 변수 자리표시자
| 변수 | 의미 | 추출 소스 (install.sh) |
|---|---|---|
| `{{site_name}}` | 사이트 표시 이름 | 디렉터리 basename |
| `{{project_name}}` | 프로젝트 식별자 | 디렉터리 basename |
| `{{site_description}}` | 한 줄 설명 | README 첫 H1 또는 빈 값 |
| `{{repo_url}}` | git remote URL | `git remote get-url origin` 또는 빈 값 |

## 확장성
같은 패턴으로 향후 `templates/license/`, `templates/contributing/`, `templates/issue-templates/` 등 트리거 시리즈 확장 예정 (Phase 3 검토).

## 멱등성 (install.sh 책임)
3단 방어: cmp 동일성 → .bak 백업 → 중복 추가 방지. install.sh가 이 정책을 강제.
