# GH_Harness Sandbox Policy (v4.1 C-lite)

**버전**: v4.1 (Phase 4.1)
**상태**: C-lite (정규식 기반 명령 검사). C-full(Docker/Firejail 격리)은 Phase 4.2에서.
**적용 지점**: `sandbox-enforce.sh` PreToolUse hook (Bash 도구 호출 전)

---

## 1. 3-Tier 정책

### BLOCK (즉시 차단 — 복구 불가)

절대 실행 금지. 에러 반환 + T2 승인 경로도 막음.

| 패턴 | 이유 |
|---|---|
| `rm\s+-rf\s+/` (루트 삭제) | 시스템 파괴 |
| `rm\s+-rf\s+~` (홈 삭제) | 사용자 데이터 전체 삭제 |
| `rm\s+-rf\s+\*` (현위치 와일드카드) | 범위 제어 불가 |
| `:(){:\|:&};:` | fork bomb |
| `mkfs\.` | 파일시스템 포맷 |
| `dd\s+.*of=/dev/` | 블록 디바이스 직접 쓰기 |
| `chmod\s+-R\s+777\s+/` | 전역 권한 개방 |
| `curl.*\|\s*sh` / `wget.*\|\s*bash` | 원격 스크립트 즉시 실행 (공급망 공격 경로) |
| `sudo\s+rm` | 관리자 권한 삭제 |

### WARN + T2 (확인 후 진행)

T2 `EXTERNAL` 또는 `SECURITY` 카테고리로 `request-user-confirm.sh` 트리거.

| 패턴 | 이유 | T2 카테고리 |
|---|---|---|
| `git\s+push\s+(-f\|--force)` | 히스토리 덮어쓰기 | EXTERNAL |
| `git\s+reset\s+--hard` | 로컬 변경 소실 | EXTERNAL |
| `git\s+clean\s+-f` | 추적되지 않은 파일 삭제 | EXTERNAL |
| `DROP\s+TABLE` / `DROP\s+DATABASE` | DB 스키마 파괴 | SECURITY |
| `TRUNCATE\s+` | 데이터 전량 삭제 | SECURITY |
| `kubectl\s+delete` | 쿠버네티스 리소스 삭제 | EXTERNAL |
| `kamal\s+(app\s+)?remove` | 배포 삭제 | EXTERNAL |
| `npm\s+publish` / `pip\s+upload` | 공개 레지스트리 배포 | EXTERNAL |
| `AWS_.*=` (inline credential) | 시크릿 노출 위험 | SECURITY |

### ALLOW (자유 실행)

위 패턴에 해당하지 않는 모든 명령. T0 처리.

---

## 2. Bypass 경로

### 긴급 우회 (로그 기록 필수)

환경변수 `HARNESS_SANDBOX_BYPASS=1` 설정 시 BLOCK도 WARN으로 강등.
단, `.claude/trace/YYYY-MM-DD.jsonl`에 `{"event":"sandbox_bypass","command":"..."}` 기록.

### T2 승인 경로

WARN 패턴은 `request-user-confirm.sh`로 대표님 컨펌 받으면 진행.
승인 이력은 registry.json의 `sandbox_approvals[]`에 기록.

---

## 3. 정책 파일 vs Hook 관계

- **정책 파일** (이 문서) = 규칙 명세 (사람이 읽는 소스 오브 트루스)
- **Hook 구현** (`sandbox-enforce.sh`) = 규칙 집행 (PreToolUse 단계)
- 불일치 발견 시 Hook 수정이 우선. 문서와 Hook 동기화는 주 1회 drift-auditor (Phase 4.3)가 검사.

---

## 4. Anti-Pattern (하네스 표류 방지)

### 금지
- 정책 파일만 있고 Hook 미구현 → 피드포워드만 있는 상태 (Fowler anti-pattern #2)
- Hook 차단 로그를 확인하지 않음 → Silent failure
- T2 컨펌 우회 습관화 → Guardrails 의미 상실

### 권장
- Hook 차단 로그 주 1회 리뷰 (오탐 개선)
- 새 프로젝트 추가 시 정책 파일 전파 확인
- 정책 위반 카운트를 dashboard에 노출 (2026-04-22 v4.1 기준 미구현 → Phase 4.2 TODO)

---

## 5. 변경 이력

| 버전 | 날짜 | 변경 |
|---|---|---|
| v4.1 | 2026-04-22 | 초안 작성 (C-lite) |
| TBD (v4.2) | - | C-full: Docker 격리, 네트워크 화이트리스트 |

---

## 6. 참고 문헌

- Martin Fowler — [Harness engineering](https://martinfowler.com/articles/harness-engineering.html) (Guardrails 섹션)
- LangChain — [The Anatomy of an Agent Harness](https://www.langchain.com/blog/the-anatomy-of-an-agent-harness) (Sandbox 챕터)
- NxCode — [Harness Engineering 2026](https://www.nxcode.io/resources/news/what-is-harness-engineering-complete-guide-2026) (Guardrails & Safety Constraints)
