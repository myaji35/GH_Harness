---
name: bmad-orchestration
description: Use when invoking BMad AU agents (/po, /architect, /qa, /ux-expert, /analyst, /pm, /dev, /bmad-orchestrator, /bmad-master, /qa-gate, /brownfield-create-epic, /brownfield-create-story) or when user requests "새 기능 추가 / MVP 개발 / 요구사항 분석 / 시스템 설계 / 사용자 스토리 작성 / 품질 검증 / 레거시 마이그레이션 / 전체 기능 개발". Routes work to BMad agents (planning/analysis/validation only) while keeping all implementation in Claude Code.
trigger: bmad
---

# BMad Superpower (AU Agent 시스템)

## 핵심 원칙

- BMad AU Agent는 **전문가 에이전트**로 계획/분석/검증을 담당
- Claude Code(나)는 **실행 엔진**으로 실제 코드 작성/수정/테스트를 담당
- 대표님의 지시에 따라 **적절한 에이전트를 자동으로 선택**하여 협업
- **충돌 해소 (Karpathy #2 Simplicity First와)**: 자동 에이전트 체인은 **요청 범위 안의 누락 방지 도구**로만 작동. 새 범위 자체 추가 금지.
  - ✅ 허용 예: "성수 분석" 요청 → /po의 Admin/User/Guest 스토리 분해 (요청 범위 안의 누락 방지)
  - ❌ 금지 예: "성수 분석" 요청 → "감사 로그 시스템도 같이 추가" 같은 자체 판단 확장

## 자동 에이전트 선택 규칙

### 1. 요구사항 및 계획 단계
| 대표님 요청 패턴 | 자동 실행 에이전트 |
|---|---|
| "새 기능 추가", "MVP 개발" | /po (Product Owner) |
| "요구사항 분석", "비즈니스 로직" | /analyst |
| "사용자 스토리 작성" | /po |

### 2. 설계 및 아키텍처 단계
| 대표님 요청 패턴 | 자동 실행 에이전트 |
|---|---|
| "시스템 설계", "아키텍처 검토" | /architect |
| "UI/UX 디자인", "컴포넌트 설계" | /ux-expert |
| "데이터베이스 스키마" | /architect |

### 3. 구현 단계 (Claude Code 단독 처리)
| 대표님 요청 패턴 | 처리 방식 |
|---|---|
| "코드 작성", "파일 수정" | Claude Code 바로 구현 |
| "버그 수정", "리팩토링" | Claude Code 바로 수정 |
| "테스트 실행" | Claude Code 바로 실행 |

### 4. 품질 검증 단계
| 대표님 요청 패턴 | 자동 실행 에이전트 |
|---|---|
| "품질 검증", "테스트 케이스 생성" | /qa |
| "코드 리뷰", "베스트 프랙티스 체크" | /dev |
| "QA 게이트 통과 확인" | /qa-gate |

### 5. 레거시 현대화 (Brownfield)
| 대표님 요청 패턴 | 자동 실행 에이전트 |
|---|---|
| "레거시 마이그레이션" | /brownfield-create-epic |
| "기존 코드 현대화" | /brownfield-create-story |
| "ERB → React 변환" | /architect + Claude Code |

### 6. 복잡한 오케스트레이션
| 대표님 요청 패턴 | 자동 실행 에이전트 |
|---|---|
| "전체 기능 개발" | /bmad-orchestrator |
| "다단계 작업" | /bmad-master |
| "프로젝트 관리" | /pm |

## 워크플로우 자동화

### 표준 개발 사이클
```
Step 1: 대표님 요청
  ↓
Step 2: 자동 판단
  - 계획 필요? → /po, /analyst
  - 설계 필요? → /architect, /ux-expert
  - 바로 구현? → Claude Code
  ↓
Step 3: 구현 (Claude Code)
  - 코드 작성
  - 파일 수정
  - 테스트 실행
  ↓
Step 4: 검증 (자동)
  - /qa → 품질 검증
  - /dev → 코드 리뷰
  ↓
Step 5: 완료 보고
  - Conventional Commits으로 커밋
  - HANDOFF.md 업데이트 (필요시)
```

### 긴급 버그 수정 사이클
```
Step 1: 대표님 "버그 수정" 요청
  ↓
Step 2: Claude Code 직접 처리
  - 원인 분석
  - 코드 수정
  - 테스트 실행
  ↓
Step 3: 자동 검증
  - /qa → 회귀 테스트 확인
  ↓
Step 4: 즉시 커밋
```

## 사용 예시

### 예시 1: 새 기능 개발
```
대표님: "InsureGraph Pro에 보험 약관 비교 기능 추가"

자동 워크플로우:
1. /po → 사용자 스토리 생성
2. /architect → 시스템 설계
3. /ux-expert → SLDS 기반 UI 설계
4. Claude Code → 실제 구현
5. /qa → 테스트 케이스 생성 및 검증
```

### 예시 2: 버그 수정
```
대표님: "탭 UI 높이 계산 오류 수정"

자동 워크플로우:
1. Claude Code → MEMORY.md 패턴 참조하여 즉시 수정
2. /qa → 회귀 테스트 확인
3. Claude Code → 커밋
```

### 예시 3: 레거시 현대화
```
대표님: "Rails ERB를 React로 마이그레이션"

자동 워크플로우:
1. /brownfield-create-story → 마이그레이션 스토리 생성
2. /architect → 컴포넌트 구조 설계
3. Claude Code → 단계별 변환 실행
4. /qa-gate → 품질 게이트 통과 확인
```

## 명시적 에이전트 호출

대표님이 특정 에이전트를 직접 지정하고 싶은 경우:
- **"architect 불러서 검토해줘"** → /architect 실행
- **"qa에게 테스트 맡겨"** → /qa 실행
- **"오케스트레이터로 전체 관리"** → /bmad-orchestrator 실행

## 금지 사항

- BMad 에이전트에게 **코드 작성을 절대 위임하지 않음**
- 에이전트는 **계획/분석/검증**만 담당
- **실제 구현은 항상 Claude Code(나)** 가 수행
