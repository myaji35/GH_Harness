# GH_Harness ↔ Linear sync

`registry.json`의 이슈를 Linear 프로젝트로 보내고, Linear에서 사람이 바꾼 상태와 우선순위를 다시 가져옵니다. Python 3 표준 라이브러리만 사용합니다.

## 포트폴리오 모드

`portfolio.json`에 등록된 개발 디렉터리마다 HAR 팀의 Linear 프로젝트 하나를 관리합니다. 프로젝트 이름·설명, 팀·워크플로 상태 이름, 이슈 라벨을 한국어로 맞춥니다. 레지스트리가 없는 디렉터리는 Linear 프로젝트만 처리합니다. 디렉터리가 없거나 레지스트리 JSON이 손상된 프로젝트는 경고 후 건너뜁니다.

```sh
python3 tools/linear_sync/portfolio_sync.py
python3 tools/linear_sync/portfolio_sync.py --only GH_Harness --json
python3 tools/linear_sync/portfolio_sync.py --apply
python3 -m unittest tools.linear_sync.test_linear_sync tools.linear_sync.test_portfolio_sync
```

기본 실행은 dry-run입니다. `--apply`에서만 Linear와 로컬 레지스트리를 수정합니다. 키가 없으면 로컬 분석 후 정상 종료합니다. 결과 요약은 `last_portfolio_run.json`에 기록하며 API 키와 원본 이슈 payload는 포함하지 않습니다. 기존 `linear_sync.py` 단일 프로젝트 모드는 수동 실행용으로 유지합니다.

새 프로젝트는 `portfolio.json`의 `projects` 배열에 `dir`, 한국어 `name`, 한국어 `summary`를 추가합니다. 기존 Linear 프로젝트를 이름 변경하며 이어 쓰려면 `linear_project_alias`에 예전 이름을 지정합니다. 레지스트리 위치는 `<base_dir>/<dir>/.claude/issue-db/registry.json`으로 고정됩니다.

워크스페이스의 모든 팀에서 활성 이슈(상태 type이 `completed`, `canceled`가 아닌 이슈)를 페이지 끝까지 실측합니다. `active_issue_cap`(기본 230)에서 현재 활성 수를 뺀 만큼만 새 이슈를 선택합니다. 프로젝트별 기존 연결 열린 이슈와 새 이슈의 합은 `per_project_quota`(기본 6)를 넘지 않습니다. 기존 연결 이슈가 이미 할당량을 넘더라도 그 이슈들은 계속 동기화하며 새 이슈만 중단합니다. 새 후보는 진행 중·사용자 대기, P0 → P3, 최신순으로 정렬하고 프로젝트를 한 번씩 돌며 배분합니다. 미연결 완료 이슈는 새로 올리지 않습니다. Linear의 상태·우선순위 변경은 기존 충돌 규칙에 따라 가져오며, 레지스트리 변경과 충돌하면 레지스트리를 우선합니다.

## 설정

Linear **Settings → Security & access → Personal API keys**에서 개인 API 키를 발급합니다. `XIM_LINEAR_API_KEY` 또는 `LINEAR_API_KEY` 환경변수로 전달하거나 `tools/linear_sync/.env`에 다음처럼 넣습니다. 환경변수가 우선합니다. 키는 화면, 요약 파일, 로그에 기록하지 않습니다.

```text
XIM_LINEAR_API_KEY=your-key-here
```

`config.json`의 `team_key`는 `HAR`로 지정되어 있습니다. 지정한 팀이 없으면 오류로 중단합니다. `team_key`가 `null`이면 워크스페이스에 팀이 하나일 때만 그 팀을 사용하며, 여러 팀이면 설정을 요구하고 쓰기 전에 중단합니다. `project_name`은 기본 `GH_Harness`이며 해당 팀에 프로젝트가 없으면 `--apply`에서 생성합니다. `use_labels`가 참이면 레지스트리 `type` 라벨을 사용하거나 생성하고, `AWAITING_USER`에는 `대표님 차례` 라벨을 붙입니다. 다른 상태가 되면 이 라벨을 뗍니다. `.env`는 개인 비밀 파일로 관리하고 버전에 추가하지 마세요.

## 실행

저장소 루트에서 실행합니다.

```sh
python3 tools/linear_sync/linear_sync.py
python3 tools/linear_sync/linear_sync.py --json
python3 tools/linear_sync/linear_sync.py --apply
python3 tools/linear_sync/linear_sync.py --apply --push-only --limit 20
python3 tools/linear_sync/linear_sync.py --apply --pull-only
python3 -m unittest tools/linear_sync/test_linear_sync.py
```

기본은 dry-run입니다. Linear 조회와 계획 출력만 수행합니다. 키가 없으면 로컬 레지스트리에서 대상, 상태 범주, 우선순위를 분석하고 종료 코드 0으로 끝납니다. `--apply`도 키가 없으면 쓰지 않습니다. 전체 결과는 `tools/linear_sync/last_run.json`에 저장하고 화면에는 상위 20건을 보여줍니다. `--limit`은 새로 올릴 후보 수를 제한하며 이미 연결된 이슈는 항상 검토합니다. `._` 파일은 읽지 않습니다.

## 매핑

| 레지스트리 상태 | Linear workflow 타입/이름 |
| --- | --- |
| BACKLOG | backlog |
| READY | backlog (AI 대기열) |
| IN_PROGRESS | started, In Progress 우선 |
| AWAITING_USER, HANDED_OFF, PARTIAL | started 중 In Review, 없으면 started |
| COMPLETED, DONE | completed |
| CLOSED, CLOSED_*, OBSOLETED, ARCHIVED | canceled |

| 레지스트리 우선순위 | Linear |
| --- | --- |
| P0 | 1 Urgent |
| P1 | 2 High |
| P2 | 3 Medium |
| P3 | 4 Low |
| 없음 | 0 |

Linear에서 바뀐 항목은 `updatedAt > payload.linear.synced_at`이고 상태 ID나 우선순위가 마지막 동기화 값과 다를 때 가져옵니다. 이때 레지스트리도 변경됐다면 레지스트리가 우선이며 충돌 목록에 남깁니다. Linear의 `completed`, `canceled`, `started`, `unstarted`, `backlog`는 각각 `COMPLETED`, `CLOSED`, `IN_PROGRESS`, `READY`, `BACKLOG`로 돌아옵니다. 단, 레지스트리의 `READY`와 Linear의 `backlog`는 동등하게 취급하여 READY를 BACKLOG로 바꾸거나 상태 충돌을 만들지 않습니다. 기존 상태가 검토 상태이고 Linear가 In Review이면 기존 상태를 유지합니다.

push는 마지막 동기화 상태 ID/타입, 우선순위, 제목, 라벨, 프로젝트와 원하는 값을 비교합니다. 모두 같으면 `unchanged`로 세고 Linear에 쓰지 않으며 `synced_at`도 유지합니다. 새 비교 필드가 없는 기존 연결 레코드는 Linear를 조회해 값이 같으면 기준 필드만 채웁니다.

Linear 제목은 레지스트리 제목 앞의 대괄호 태그를 제거하고 공백을 정리합니다. `AWAITING_USER`는 `확인할 것 — `을 붙입니다. 설명에는 ISS ID를 포함한 `원제목`, `type`, `priority`, `payload.ref`, `payload.origin`, `created_at`, 레지스트리 경로가 들어갑니다. 다른 payload 필드는 보내지 않습니다. 제목과 설명의 비밀번호 토큰 및 API 키 패턴은 `[가림]`으로 대체하며 레지스트리 원본은 그대로 둡니다.

## 무료 요금제 한도

기본 `max_open_issues`는 220으로, 무료 요금제의 250개 제한보다 여유를 둡니다. 대상이 넘으면 P0 → P1 → P2 → P3, 같은 우선순위에서는 최신순으로 새 후보를 자르고 경고합니다. 기존에 연결된 이슈는 닫힌 상태라도 동기화 대상에 남습니다. 완료 이슈 중 최근 `done_window_days`(기본 14일) 이내의 항목도 후보입니다.

## 자동 실행

Claude Code 세션의 Stop 훅에서 `tools/linear_sync/hook-sync.sh`를 실행합니다. `tools/linear_sync/.env`가 없으면 동기화하지 않습니다. 스탬프 파일 `~/.cache/gh-harness/linear-sync.stamp`가 최근 600초 이내에 갱신됐거나 `linear_sync.py` 또는 `portfolio_sync.py`가 이미 실행 중이면 건너뜁니다. 그 외에는 스탬프를 갱신하고 저장소 루트에서 `python3 tools/linear_sync/portfolio_sync.py --apply`를 백그라운드로 실행하므로 Stop 훅이 동기화 완료를 기다리지 않습니다. 실행 로그는 `~/Library/Logs/gh-harness-linear-sync.log`에 기록됩니다.

macOS의 `launchd` 에이전트는 외장 디스크의 스크립트를 읽을 때 TCC 권한 문제로 실패할 수 있어 자동 실행 방법으로 권장하지 않습니다. 기존 에이전트를 설치했다면 `bash tools/linear_sync/install-launchd.sh --uninstall`로 등록 해제할 수 있습니다. 네트워크/레이트리밋 오류는 최대 세 번 지수 백오프로 재시도하고 해당 이슈의 실패로 기록합니다.
