# Git Worktree 워크플로우 (v4.2+)

Harness 시스템에서 **병렬 에이전트/세션**을 격리하기 위해 git worktree를 표준 도구로 채택한다. 기반 문헌은 `docs/incident-report-*` 시리즈와 외부 레퍼런스(Claude Code 공식 `--worktree` 지원, incident.io, parallel-code repo, dandoescode)이다.

## 왜 필요한가

- Claude Code + 에이전트가 **같은 디렉토리**에서 병렬 실행되면 편집이 충돌한다
- `git clone` 반복은 비효율 (전체 히스토리/의존성 재설치)
- `git worktree`는 **동일 .git 공유 + 독립 working dir** → 병렬 실행의 정답

## 구성 요소

| 구성 | 위치 | 역할 |
|---|---|---|
| `w` CLI | `~/.local/bin/w` (→ `GH_Harness/bin/w.sh`) | worktree 생성/전환/삭제 헬퍼 |
| `.claude/worktrees.json` | 각 프로젝트 루트 | worktree별 포트 offset 저장 |
| `.harness-worktree-meta` | 각 worktree 루트 | 메인 루트 경로, 포트 offset, worktree 이름 |
| `.gitignore` 자동 패턴 | 각 프로젝트 루트 | worktree 메타 파일 커밋 차단 |

## 사용법

```bash
# 기본: worktree 생성 + shell 드롭인
w 0012_InsureGraph\ Pro feat-risk-score

# Claude Code를 해당 worktree에서 시작
w 0012_InsureGraph\ Pro feat-risk-score claude

# 임의 명령 실행
w 0012_InsureGraph\ Pro feat-risk-score -- bun run dev

# 목록
w list
w list 0012_InsureGraph\ Pro

# 정리 (worktree + 브랜치 둘 다 삭제)
w rm 0012_InsureGraph\ Pro feat-risk-score
```

## 자동화되는 것

1. **브랜치 자동 생성**: `wt/<USER>/<feature>` 형식
2. **공유 심볼릭**: `node_modules`, `.next`, `.venv`, `venv`, `vendor`, `bundle`, `.swc`, `.turbo`, `.cache`
   - 메인 디렉토리의 것을 symlink → `bun install`/`npm install` 반복 불필요
3. **포트 offset 할당**: worktree마다 +1씩. `.harness-worktree-meta`의 `HARNESS_PORT_OFFSET`
4. **`.gitignore` 패턴 주입**: `.claude/worktrees`, `worktrees/`, `.harness-worktree-meta`, `.claude/worktrees.json`

## 병렬 에이전트 패턴

여러 이슈를 동시에 처리할 때:

```bash
# 터미널 1
w 0014_Townin\ Graph ISS-042 claude

# 터미널 2
w 0014_Townin\ Graph ISS-043 claude

# 터미널 3
w 0014_Townin\ Graph ISS-044 claude
```

각 세션은 자신만의 worktree에서 편집 → 충돌 없음. 완료되면 각자 PR 생성.

## 포트 offset 활용 (개발 서버 충돌 방지)

각 worktree는 `.harness-worktree-meta`에 offset을 갖는다:

```bash
# worktree 안에서
source .harness-worktree-meta
export PORT=$((3000 + HARNESS_PORT_OFFSET))
bun run dev   # main은 3000, feat-x는 3001, feat-y는 3002
```

프로젝트별 start 스크립트에 이 패턴을 적용하면 여러 worktree에서 동시에 dev 서버를 띄워도 포트 충돌이 없다.

## 주의사항

- `rm -rf <worktree>` 직접 지우지 말 것 → `w rm` 사용 (git 메타 정리 포함)
- 같은 브랜치명을 두 worktree에서 체크아웃 불가 (git이 방지)
- `bundle install`/`bun install`을 worktree에서 실행하면 symlink 대상(main의 `node_modules`)이 변조됨 → 메인 디렉토리에서만 install
- worktree 안에서 `git push` 가능. 원격 공유 `.git` 참조

## harness 이슈 파이프라인과의 결합 (향후 RACE_MODE)

지금은 수동 워크플로우. 설계 단계 후속:
- `RACE_MODE` 이슈 타입 → 한 이슈를 Claude/Codex/Gemini가 각 worktree에서 동시 처리
- `eval-harness`가 3안 자동 점수화 → 최고안 머지
- 3단계 작업으로 별도 컨펌 후 진행

## 참고 레퍼런스

- [Claude Code Docs — Common Workflows](https://code.claude.com/docs/en/common-workflows) (`--worktree` 공식)
- [incident.io — Shipping faster with Claude Code and Git Worktrees](https://incident.io/blog/shipping-faster-with-claude-code-and-git-worktrees)
- [johannesjo/parallel-code](https://github.com/johannesjo/parallel-code)
- [Dan Does Code — Parallel Vibe Coding with Git Worktrees](https://www.dandoescode.com/blog/parallel-vibe-coding-with-git-worktrees)
