---
name: download-organizer
description: Use when 다운로드 폴더 정리("다운로드 정리", "organize downloads") 또는 구글드라이브 내부에 이미 쌓인 파일 정리("구글드라이브 정리", "드라이브 파일명 정리", "드라이브 폴더 재배치", "드라이브 파일 N개 정리") 요청 시. 파일을 룰베이스로 분류·리네임하고 rclone(gdrive:)으로 이동한다. 다운로드→드라이브 이동은 옵시디언 노트 생성, 드라이브 내부 재배치는 회사/법인 1순위 폴더 구조로 정리.
---

# Download Organizer (다운로드 → 구글드라이브 아카이브 + 옵시디언 지식화)

## Overview
다운로드 폴더에 쌓인 파일을 **반자동(제안→승인→실행)**으로 정리한다. 룰베이스 분류 우선, 애매한 것만 AI. rclone `move`로 구글드라이브에 단방향 이동(싱크 아님)하고 로컬은 비운다. 각 파일마다 옵시디언 노트를 생성해 지식화한다.

**철학**: 파일 실체는 구글드라이브 5TB에, 지식(메타+요약+링크)은 옵시디언에.

## 핵심 원칙 (반드시 지킬 것)
- **반자동**: 절대 조용히 대량 이동/삭제하지 않는다. plan 미리보기 표를 대표님께 보여주고 승인받는다.
- **삭제 안전**: rclone `moveto`가 업로드→검증→로컬삭제를 처리. 검증(원격 존재 + 로컬 삭제) 실패 시 그 파일은 건너뛴다.
- **임시/쓰레기는 이동 X, 삭제**: HEIC 임시 소통용, 프린터 테스트페이지 등은 대표님 확인 후 완전삭제.
- **미분류 최소화**: 분류 규칙으로 안 잡히면 파일 내용(pdftotext/이미지)을 열어 확정.

## 권장 모델 (경제성 기준)
- **분류·리네임·이동**: 스크립트(plan.py/execute.py)가 처리 → AI 모델 거의 불필요.
- **애매 파일 판별**(PDF 몇 줄/이미지 보고 분류): **Haiku 4.5** (`claude-haiku-4-5-20251001`). 가벼운 판단이라 가장 경제적. 서브에이전트로 위임 시 `model: haiku`.
- Opus/Sonnet 불필요 — 이 작업은 판단 난이도가 낮다.

## 사전 요구 (한 번만)
- `rclone` 설치 + `gdrive:` remote 인증 (scope=drive full access). 확인: `rclone lsd gdrive:`
- ⚠️ **구글드라이브 경로 주의**: `gdrive:` 루트가 곧 "내 드라이브". `gdrive:내 드라이브/...`로 쓰면 잘못된 중간폴더가 생긴다. 반드시 `gdrive:Project/...`, `gdrive:Document/...`.
- 옵시디언 메인 볼트: `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Obsidian` (환경변수 `OBSIDIAN_VAULT`로 재정의 가능)

## 워크플로우

### 1. 미리보기 (읽기전용, 파일 안 건드림)
```bash
# 다운로드 폴더 지정 (기본 ~/Downloads). E_SSD 등은 DL_DIR로.
python3 ~/.claude/skills/download-organizer/scripts/plan.py
```
plan.json 생성 + 분류 요약 출력. **미분류 항목은 내용을 열어 규칙에 반영**(scripts/plan.py의 RULES 편집).

### 2. 미리보기 표를 대표님께 제시 → 승인 대기 (STOP)
카테고리별 분류·리네임 결과를 표로 보여준다. 삭제 대상(임시/쓰레기)이 있으면 명시하고 확인받는다.

### 3. 삭제 대상 처리 (승인 후)
임시/쓰레기 파일은 `rm`으로 완전삭제. 뭘 지우는지 목록 명시.

### 4. 이동 실행 (승인 후)
```bash
# 특정 카테고리만 시범 이동 (첫 실행은 시범 권장)
python3 ~/.claude/skills/download-organizer/scripts/execute.py "심티어"
# 검증 후 전체
python3 ~/.claude/skills/download-organizer/scripts/execute.py ALL
```
각 파일: rclone moveto(업로드→검증→로컬삭제) → 옵시디언 노트 생성 → 인덱스 갱신 → moved.jsonl 로그.

### 5. 완료 판정 (⚠️ 필수 — 검증 없이 "완료" 보고 금지)
**대량 이동은 백그라운드 exit 0이 와도 미완일 수 있다** (중간 종료·누락). 반드시 아래 3개를 실제 수치로 확인한 뒤에만 완료 보고:
1. **로컬 잔여 파일 수 = 0** — `find "$DL_DIR" -maxdepth 1 -type f ! -name '.*' | wc -l` (폴더 제외). 0이 아니면 **execute ALL 재실행**(이미 이동된 건 로컬에 없어 자동 스킵) → 다시 검증. 0 될 때까지 반복.
2. **moved.jsonl 개수 = plan 대상 개수** — `wc -l "$ORGANIZER_WORK/moved.jsonl"`
3. **구글드라이브 도착 + 옵시디언 노트** — `rclone lsf gdrive:<dest>/`, `ls "$VAULT/📥아카이브"/*.md`

## 폴더 체계 (scripts/plan.py의 RULES에 반영)
- `Project/SMG/{의료바이오금융,AI데이터센터,홈즈페이}/` — 신라메디컬그룹 산하
- `Project/{XimTier,누리팜,InsureGraph,Phoenix,ProofLayer}/` — 독립사업
- `주식회사 가가호호/법인설립/`, `Document/{청구서,계약서,보안사고,실사검증,회의록,AI분석보고서,산업기술,애드센스,인보이스,이벤트,사진_미분류}/`

## 리네임 규칙
`YYYY-MM-DD_카테고리_주제.확장자` (날짜: 파일명 내 YYMMDD/YYYYMMDD/한글날짜 → 없으면 수정일). 한글은 NFC 정규화 + 문자 단위 30자 컷.

## Common Mistakes
- ❌ `gdrive:내 드라이브/` 프리픽스 → 잘못된 폴더 생성. `gdrive:Project/...`로 직접.
- ❌ 미리보기 없이 바로 ALL 실행 → 오분류 대량 발생. 항상 시범 카테고리 먼저.
- ❌ 폴더(디렉토리)는 이 스크립트가 파일만 처리 → 폴더는 별도 판단.
- ❌ 새 프로젝트/카테고리 등장 시 RULES 미갱신 → 미분류. 규칙 추가 후 재실행.
- ❌ **백그라운드 exit 0을 완료로 착각** (2026-07-01 E_SSD 사고: 335개 중 222개만 이동됐는데 "완료" 보고). exit 0 ≠ 이동완료. 반드시 로컬 잔여 파일 수로 검증하고, 남아있으면 execute ALL 재실행 반복.

## 확장: 다른 다운로드 폴더
```bash
DL_DIR="/Volumes/E_SSD/Download" python3 ~/.claude/skills/download-organizer/scripts/plan.py
```

---

# 모드 B: 구글드라이브 내부 정리 (이미 쌓인 파일 재배치)

로컬 다운로드가 아니라 **드라이브 안에 흩어진 파일**을 파일명 규칙화 + 폴더 재배치한다. 트리거: "구글드라이브 정리", "드라이브 파일 N개 정리". 인프라(rclone gdrive:, 반자동 게이트, 폴더 체계)는 모드 A와 공유.

## 확정 정책 (대표님, 2026-07-07)
- **하루 100개** 처리 (초과 금지). "N개 정리" 지시 시 N을 상한으로.
- **분류 축 = 회사/법인 1순위 → 문서종류 2단계**. 예: `주식회사 가가호호/{세무,인사,청구영수,회의록}`, `주식회사 가가호호/사랑과선행/인사`, `Project/{누리팜,아인스}`, `Document/개인_강승식/{관리비,세무,금융}`, `Document/보험영업_FP/`, `Document/참고자료`.
  - `(주)사랑과선행` = 가가호호 계열 운영시설. `아인스` = 빅데이터 협력사. `누리팜` = 괴산 사리면 부지.
- **중복 먼저 스캔** → 승인 → 제거 → 재배치.
- **반자동 게이트 유지**: 제안 표 → 승인 → 실행.

## 워크플로우
```bash
SK=~/.claude/skills/download-organizer/scripts; W=<작업디렉토리>
# 1) 중복 스캔 (md5 동일). 의미있는 이름 KEEP, 카톡/UUID/사본 제거후보.
python3 $SK/gdrive_dup_scan.py "gdrive:" "$W"   # → dup_report.json (표로 제시), dup_remove_list.json
# 2) [승인 후] 중복 제거: dup_remove_list.json의 경로들을 rclone deletefile
# 3) 분류: 루트 실파일 중 오늘분 N개 → plan.json 작성
#    - 이름·확장자 룰 우선. 이름으로 법인 불명하면 내용(상호·사업자번호) 열어 확인.
#    - ⚠️ 무의미 파일명(UUID/숫자/확장자없음)은 반드시 내용 확인 — 핵심 서류일 수 있음
#      (2026-07-07: 20191229_223125.jpg가 가가호호 사업자등록증이었음).
# 4) [승인 후] 실행 (재실행 안전 — 이미 이동된 건 자동 스킵):
python3 $SK/gdrive_apply.py "$W/plan.json" "gdrive:" "$W"   # → DONE ok/deleted/skip/fail
```

## 완료 판정 (⚠️ 필수 — 출력만 믿지 말 것)
1. **루트 파일 수 감소분 = 처리 대상 수**: `rclone lsf gdrive: --files-only | wc -l` (전후 비교)
2. **gdrive_moved.jsonl 건수 확인**
3. **신규 폴더 도착 확인**: `rclone lsf "gdrive:주식회사 가가호호/세무/"` 등

## 모드 B Common Mistakes
- ❌ **NFC 정규화 누락** (2026-07-07 대량 삽질): macOS/rclone 파일명은 NFD(자모분리)라 파이썬 `"관리비" in name` 매칭이 통째로 실패. **키워드 매칭 전 `unicodedata.normalize("NFC")` 필수.** 두 스크립트에 내장됨.
- ❌ 무의미 파일명을 이름만 보고 미분류 처리 → 핵심 서류 매몰. UUID/숫자/확장자없음은 내용 확인.
- ❌ 확장자 없는 파일 = 구글 네이티브 문서 아님. `file` 명령으로 실제 타입 확인(PPTX/PDF/ZIP가 확장자만 유실된 경우 많음).
- ❌ rclone `lsjson --hash`에서 md5 없는 것 = 구글 네이티브 문서(시트/닥). 이들은 중복스캔·리네임 대상 아님. 실제 다운로드 파일만 md5 있음.
