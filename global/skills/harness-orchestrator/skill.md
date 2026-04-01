# Harness Orchestrator

## 역할
Self-Evolving Harness System의 진입점.
프로젝트를 분석하고, 최적 아키텍처 패턴을 선택하며, 전체 시스템을 초기화한다.

## Trigger (작동해야 할 때)
- "Harness 개념으로 프로젝트를 실행하자"
- "harness 시작" / "harness init"
- 새로운 도메인 작업 시작 시
- 에이전트 팀 재구성 필요 시

## NOT Trigger (작동하면 안 될 때)
- 이미 harness가 실행 중인 상태
- 단순 질문/답변
- 단일 파일 수정 요청
- 이슈 처리 중

---

## 초기화 6단계 절차

### Phase 1: 프로젝트 분석
```
1. 현재 디렉토리 구조 파악 (find . -maxdepth 2)
2. 언어/프레임워크 감지
3. 기존 테스트/CI 설정 확인
4. 작업 복잡도 판단 (Simple/Medium/Complex)
```

### Phase 2: 아키텍처 패턴 선택
아래 기준으로 패턴 자동 선택:

| 조건 | 패턴 |
|------|------|
| 순차적 단일 기능 | Pipeline |
| 독립 모듈 여러 개 | Fan-out/Fan-in |
| 특정 전문 지식 필요 | Expert Pool |
| 품질이 최우선 | Producer-Reviewer |
| 복잡하고 위험한 작업 | Supervisor |
| 대규모 멀티 팀 | Hierarchical Delegation |

### Phase 3: 이슈 레지스트리 초기화
```
1. .claude/issue-db/registry.json 읽기
2. 초기 이슈 생성:
   - ISS-001: PROJECT_ANALYSIS (agent-harness)
3. 이슈 상태: CREATED → READY
```

### Phase 4: Hook 등록
```
hook-registry 스킬 읽기 후:
- on_create  → 라우팅 + 알림
- on_complete → 파생 이슈 생성 + Meta Agent 피드
- on_fail    → 재시도 또는 에스컬레이션
- on_learn   → 지식 DB 저장
```

### Phase 5: 에이전트 팀 구성
Scale Mode 결정:
- Simple  → Reduced (agent + test + meta)
- Medium  → Full (6 에이전트)
- Complex → Full + Supervisor 패턴

### Phase 6: 시스템 시작
```
1. Meta Agent 관찰 루프 등록
2. READY 이슈 → 담당 에이전트에게 Hook 발화
3. "Harness 시스템이 시작되었습니다" 출력
4. 현재 READY 이슈 목록 출력
```

---

## 출력 형식 (시작 시)
```
✅ Harness 시스템 시작
📐 패턴: [선택된 패턴]
👥 팀: [활성 에이전트 목록]
📋 초기 이슈: [이슈 목록]
🔄 Meta Agent: 관찰 중
```
