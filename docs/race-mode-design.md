# RACE_MODE 설계 (v4.3)

동일 태스크를 여러 LLM provider가 각자의 **git worktree에서 동시에 구현**하고, 자동 판정(`race-judge.sh`)으로 승자를 선정해 메인에 머지하는 하네스 기능.

## 목적
1. 확증 편향 제거 — 같은 문제를 여러 모델이 독립적으로 풀어 교차 검증
2. 품질 상승 — 최고의 구현만 남음 (lint/테스트/diff 크기 기반 자동 채점)
3. 에이전트 경쟁 — 모델별 강점 비교 통계 축적 (learning)

## 이슈 타입 & 스키마

```json
{
  "id": "ISS-300",
  "type": "RACE_MODE",
  "title": "RACE: <원본 이슈 제목>",
  "priority": "P1",
  "status": "READY",
  "payload": {
    "source_issue": "ISS-245",
    "source_type": "GENERATE_CODE",
    "task_brief": "<에이전트에게 던질 프롬프트 핵심>",
    "providers": ["claude", "codex", "gemini"],
    "target_files": ["src/foo.ts"],
    "base_branch": "main",
    "timeout_sec": 900,
    "judge_criteria": {
      "lint": 30,
      "tests": 40,
      "diff_size": 15,
      "files_scope": 15
    }
  }
}
```

## Provider 정의
`~/.local/bin`에 CLI가 있는 경우에만 참가. provider 별로:

| Provider | CLI | worktree 내 실행 명령 |
|---|---|---|
| claude | `claude` | `claude --worktree <dir> <prompt>` 또는 stdin |
| codex | `codex` | `codex exec <prompt>` |
| gemini | `gemini` | `gemini <prompt>` |
| ollama | `ollama run <model>` | 로컬 폴백 |

프롬프트는 공통 템플릿(`task_brief` + 파일 컨텍스트).

## 실행 흐름

```
1. RACE_MODE 이슈 READY
   └─ dispatch-ready가 race-dispatch.sh 호출
2. race-dispatch.sh:
   a. 각 provider마다 worktree 생성 (w.sh 재사용)
      브랜치: race/<ISS-id>/<provider>
   b. 백그라운드로 병렬 실행, stdout을 로그로 캡처
   c. 전체 타임아웃 대기 (기본 15분)
3. race-judge.sh:
   a. 각 worktree에서 lint, test, diff stat 수집
   b. judge_criteria 가중 점수 계산
   c. 승자 선정 → 메인 브랜치로 cherry-pick 또는 머지 제안
   d. 패자 worktree는 보관 (learning용, 수동 정리)
4. on_complete가 결과 기록:
   - result.winner = "claude"
   - result.scores = {claude: 87, codex: 79, gemini: 62}
   - registry.knowledge.success_patterns에 추가
```

## 자동 판정 공식 (기본)

```
score = 0.30 * lint_score        # 0=에러, 100=클린
      + 0.40 * test_score        # 실패테스트 비율 역산
      + 0.15 * diff_score        # |scope| 밖 변경 패널티
      + 0.15 * files_score       # target_files만 건드렸는가
```

- **실격**: lint 에러 >= 10개 또는 테스트 미통과 50% 이상
- **동점**: 가장 짧은 diff 우선 (Occam)
- **사람 승자 지정**: `RACE_MODE` 이슈를 T2 컨펌으로 전환 가능 (payload.requires_user_confirm = true)

## 비용 가드

- 기본 providers는 **2개 (claude + codex)**. `gemini`, `ollama`는 opt-in
- Opus 예산 Hard Cap 근접 시 자동으로 provider 수 감축 (opus-budget-check.sh 통합)
- RACE_MODE 동시 실행 **최대 1개** (동시 N worktree는 포트/DB 충돌 위험)

## 안전장치

1. `base_branch` 기준 clean이 아니면 실격
2. worktree 외부 파일 수정 시 감점
3. `git push` 금지 (판정 전 업스트림 반영 차단)
4. 판정 후 승자 브랜치만 남기고 패자 worktree는 `/tmp/harness-race-losers/<ISS-id>/<provider>` 로 이동 (디스크 청소용)

## 트리거

```
대표님이 "레이스 모드로 해줘", "race mode", "여러 LLM으로 붙여봐"
→ 현재 IN_PROGRESS 이슈를 RACE_MODE로 승격 (또는 신규 생성)
→ race-dispatch 호출
```

## Phase 1 범위 (이번 구현)

- ✅ RACE_MODE 이슈 타입 + 스키마
- ✅ race-dispatch.sh (worktree 생성 + 병렬 실행 + 타임아웃)
- ✅ race-judge.sh (lint/test/diff 기반 자동 채점)
- ✅ axis-router 라우팅
- ✅ on_complete 연동 (결과 기록)
- ✅ CLAUDE.md 트리거 문서화
- ⏸️ provider 전환 자동 강등 (v4.4)
- ⏸️ T2 사람 승자 지정 모드 (v4.4)
- ⏸️ 패자 worktree learning 분석 (v4.5)
