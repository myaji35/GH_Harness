#!/bin/bash
# secret-guard.sh — PreToolUse(Bash) + PostToolUse(Write|Edit) hook
# API 키/시크릿 평문 노출을 커밋 단계에서 물리적으로 차단한다.
#
# 근거: 2026-06-12~13 Gemini API 키 유출 사고 — GitHub 공개 커밋된 키를
#       스캐닝 봇이 수집해 gemini-3.5-flash로 1,735만 토큰 폭주.
#       사람의 주의력이 아닌 파이프라인이 강제해야 재발을 막는다.
#
# 동작:
#   PreToolUse(Bash):    git commit/push 명령 감지 → staged 파일 시크릿 스캔 → 발견 시 exit 2(차단)
#   PostToolUse(Write|Edit): 방금 수정한 파일에 시크릿 하드코딩 시 → 경고(차단 아님)

# ── 시크릿 탐지 정규식 (단일 진실 소스) ───────────────────────────────
# placeholder/예시값은 제외하기 위해 <YOUR_...>, ${...}, xxx 류는 매칭에서 빠진다.
SECRET_REGEX='AIza[0-9A-Za-z_-]{35}|sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|(api[_-]?key|secret|token|password)["'\'' ]*[=:]["'\'' ]*[A-Za-z0-9_\-]{16,}'

scan_text() {
  # stdin 텍스트에서 시크릿 패턴 추출 (placeholder 제외)
  grep -nEo "$SECRET_REGEX" 2>/dev/null \
    | grep -viE 'YOUR_|<.*>|\$\{|xxxx|example|placeholder|changeme|REDACTED' \
    || true
}

INPUT=$(cat)
TOOL=$(echo "$INPUT" | python3 -c "import sys,json;print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)

# ── PreToolUse(Bash): git commit/push 차단 ──────────────────────────
if [ "$TOOL" = "Bash" ]; then
  CMD=$(echo "$INPUT" | python3 -c "import sys,json;print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)
  # git commit 또는 git push 명령만 검사
  case "$CMD" in
    *"git commit"*|*"git push"*)
      # staged diff에서 추가된 라인(+)만 스캔
      STAGED=$(git diff --cached 2>/dev/null | grep '^+' | grep -v '^+++')
      HITS=$(echo "$STAGED" | scan_text)
      if [ -n "$HITS" ]; then
        echo "🚨 [Harness Secret-Guard] 커밋 차단: staged 변경에 시크릿(API 키) 평문 감지" >&2
        echo "    아래 패턴이 커밋되려 합니다 (값 일부 마스킹):" >&2
        echo "$HITS" | sed -E 's/(.{12}).*/\1***REDACTED***/' | head -10 >&2
        echo "" >&2
        echo "    조치: 키를 환경변수/kamal secrets로 옮기고 .gitignore 처리 후 재커밋하세요." >&2
        echo "    근거: 2026-06 Gemini 키 유출 사고 (GitHub 공개 커밋 → 봇 수집 → 폭주)" >&2
        exit 2
      fi
      ;;
  esac
  exit 0
fi

# ── PostToolUse(Write|Edit): 수정 파일 시크릿 경고 ──────────────────
if [ "$TOOL" = "Write" ] || [ "$TOOL" = "Edit" ]; then
  FP=$(echo "$INPUT" | python3 -c "import sys,json;print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)
  [ -z "$FP" ] || [ ! -f "$FP" ] && exit 0
  HITS=$(scan_text < "$FP")
  if [ -n "$HITS" ]; then
    echo "⚠️  [Harness Secret-Guard] $FP 에 시크릿(API 키) 평문 감지" >&2
    echo "$HITS" | sed -E 's/(.{12}).*/\1***REDACTED***/' | head -5 >&2
    echo "    → 환경변수로 옮기세요. 커밋 시 secret-guard가 차단합니다." >&2
  fi
  exit 0
fi

exit 0
