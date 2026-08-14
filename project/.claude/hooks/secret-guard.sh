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
#
# ⚠️ v2 (2026-07-15): 값 부분 문자 클래스를 [A-Za-z0-9_-] → [^[:space:]"'] 로 확장.
#    근거: 2026-07-15 Vultr root 비번 5개월 공개 유출. 비번에 !]@[}) 등 특수문자가
#    포함돼 기존 [A-Za-z0-9_-]{16,}에 매칭되지 않아 통과했다.
#    즉 "강한 비밀번호일수록 탐지를 못 하는" 역설이 있었다.
#    또한 오늘 실제 발견된 2개 형태를 추가로 커버한다:
#      (a) sshpass -p 'xxx'  — 배포 스크립트 하드코딩
#      (b) 로그인: `id` / `pw` — 문서(CLAUDE.md)에 적힌 계정정보
SECRET_REGEX='AIza[0-9A-Za-z_-]{35}|sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|(api[_-]?key|secret|token|password|passwd|pwd|ssh_pass[a-z_]*)["'\'' ]*[=:]["'\'' ]*[^[:space:]"'\'']{8,}|sshpass[[:space:]]+-p[[:space:]]*["'\''][^"'\'']{6,}["'\'']|(로그인|계정|비밀번호|접속)[^\n]{0,12}[`"'\''][^`"'\'' ]{3,}[`"'\''][[:space:]]*/[[:space:]]*[`"'\''][^`"'\'' ]{6,}[`"'\'']'

# ── 시크릿 "파일명" 차단 (v2, 2026-07-15) ─────────────────────────────
# 값 패턴과 무관하게 파일명 자체로 차단한다. 정규식이 못 잡는 형태를 막는 2차 방어선.
# 근거: .deploy_credentials 는 첫 줄에 "절대 Git 커밋 금지!"라고 적혀 있었으나
#       .gitignore 미등록 + 값이 정규식을 빠져나가 5개월간 공개 노출됐다.
SECRET_FILE_REGEX='(^|/)\.deploy_credentials$|(^|/)\.env$|(^|/)\.env\.(production|prod|local|staging)$|(^|/)SECURITY_CREDENTIALS\.md$|(^|/)(config/)?master\.key$|(^|/)credentials\.json$|\.pem$|\.p12$|(^|/)id_(rsa|ed25519)$|(^|/)service-account.*\.json$|\.gcp-key\.json$'

scan_staged_filenames() {
  # staged 파일 중 시크릿 파일명 패턴 (example/template/sample 은 제외)
  git diff --cached --name-only 2>/dev/null \
    | grep -E "$SECRET_FILE_REGEX" \
    | grep -viE 'example|template|sample|\.enc$' \
    || true
}

scan_text() {
  # stdin 텍스트에서 시크릿 패턴 추출 (placeholder 제외)
  # ⚠️ -i 필수 (v2, 2026-07-15): 정규식은 소문자 password/api_key로 쓰여 있으나
  #    실제 코드는 SSH_PASSWORD= / API_KEY= 처럼 대문자가 대부분이다.
  #    -i 누락으로 대문자 변수명이 전부 통과했다 (Vultr root 비번 5개월 노출의 직접 원인).
  grep -niEo "$SECRET_REGEX" 2>/dev/null \
    | grep -viE 'YOUR_|<.*>|\$\{|\$\(|\$[A-Za-z_]|xxxx|example|placeholder|changeme|REDACTED|your_|_here' \
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
      # [v2] 1차 방어선: 시크릿 파일명 자체를 차단 (값 패턴 무관)
      FILE_HITS=$(scan_staged_filenames)
      if [ -n "$FILE_HITS" ]; then
        echo "🚨 [Harness Secret-Guard] 커밋 차단: 시크릿 파일이 staged 되었습니다" >&2
        echo "$FILE_HITS" | sed 's/^/      - /' >&2
        echo "" >&2
        echo "    조치: git rm --cached <파일> 로 추적 해제 후 .gitignore에 등록하세요." >&2
        echo "    근거: 2026-07-15 .deploy_credentials 공개 유출 (Vultr root 비번 5개월 노출)." >&2
        echo "          파일 첫 줄에 '절대 Git 커밋 금지!'라고 적혀 있었으나 게이트가 없었다." >&2
        exit 2
      fi

      # 2차 방어선: staged diff에서 추가된 라인(+)만 값 패턴 스캔
      #
      # 테스트 픽스처 제외 (2026-07-15): tests/ 아래 파일은 secret-guard 자신의
      # 탐지 능력을 검증하려고 일부러 가짜 시크릿 문자열을 담는다. 이를 차단하면
      # 게이트를 테스트할 수 없다 — 실제 유출 사례를 회귀 테스트로 고정하는 것이
      # 이 사고의 재발 방지책이므로, 테스트 파일은 스캔 대상에서 뺀다.
      # (tests/ 밖의 모든 파일은 그대로 검사한다)
      # test/ (Rails·Minitest) 와 tests/ (일반) 양쪽 + spec/ (RSpec) 을 제외한다.
      # 2026-07-15: tests/* 만 제외해 CPOFlow(test/ 단수)의 픽스처
      # `u.password = "password123"` 이 차단됐다. 테스트 픽스처의 가짜 비번은
      # 시크릿이 아니다. 단, 이름에 test가 들어가도 앱 코드면 검사 대상이다.
      STAGED=$(git diff --cached -- . \
                 ':(exclude)tests/*' ':(exclude)test/*' ':(exclude)spec/*' \
                 ':(exclude)*_test.sh' ':(exclude)*_test.rb' ':(exclude)*_spec.rb' \
                 ':(exclude)*.test.ts' ':(exclude)*.spec.ts' \
               2>/dev/null | grep '^+' | grep -v '^+++')
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
