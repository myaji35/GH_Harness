#!/usr/bin/env bash
# harness_test.sh — GH_Harness 자체 회귀 테스트
#
# 왜 존재하는가:
#   2026-07-15 감사에서 8개 결함이 발견됐다. 그중 어느 것도 CI가 잡지 못했다.
#   CI는 bash -n(문법)과 JSON 파싱만 봤기 때문이다.
#   가장 뼈아픈 것: 에이전트 24개 중 22개가 frontmatter 누락으로 4개월간
#   한 번도 스폰되지 않았는데, 그것을 감시했어야 할 meta-agent 자신이
#   스폰 불가 상태였다. 관찰자가 자기 부재를 관찰하지 못하는 구조였다.
#
#   이 파일은 그 결함들을 "다시는 조용히 재발하지 않도록" 코드로 고정한다.
#
# 의존성 없음 (bats 불필요) — CI에서 설치 없이 즉시 실행.
# 사용법: bash tests/harness_test.sh
# 종료코드: 0 = 전부 통과, 1 = 실패 있음

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

PASS=0; FAIL=0; SKIP=0
FAILED_NAMES=()

ok()   { PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); printf '  \033[31m✗\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '      → %s\n' "$2"; }
skip() { SKIP=$((SKIP+1)); printf '  \033[33m-\033[0m %s (skip: %s)\n' "$1" "${2:-}"; }
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# 실파일만 (macOS AppleDouble ._* 제외 — 외장 exFAT에서 대량 생성됨)
real_files() { find "$1" -maxdepth 1 -type f -name "$2" ! -name '._*' 2>/dev/null | sort; }

# ─────────────────────────────────────────────────────────────
section "1. 에이전트 등록 (2026-07-15: 22/24 스폰 불가였음)"
# ─────────────────────────────────────────────────────────────

agents=$(real_files "global/agents" "*.md")
total=$(printf '%s\n' "$agents" | grep -c . | tr -d ' \n')
total=${total:-0}

missing_fm=""
for f in $agents; do
  [ "$(head -c 3 "$f" 2>/dev/null)" = "---" ] || missing_fm="$missing_fm $(basename "$f" .md)"
done
if [ -z "$missing_fm" ]; then
  ok "에이전트 ${total}개 전부 YAML frontmatter 보유"
else
  no "frontmatter 누락 → Claude Code가 서브에이전트로 등록하지 않음" "누락:$missing_fm"
fi

# frontmatter 필수 키
bad_keys=""
for f in $agents; do
  fm=$(awk 'NR==1&&/^---$/{p=1;next} p&&/^---$/{exit} p' "$f" 2>/dev/null)
  for k in name description model; do
    echo "$fm" | grep -qE "^${k}:" || bad_keys="$bad_keys $(basename "$f" .md):${k}"
  done
done
[ -z "$bad_keys" ] && ok "frontmatter 필수 키(name/description/model) 완비" \
                   || no "frontmatter 키 누락" "$bad_keys"

# name 필드가 파일명과 일치 (불일치 시 스폰 이름이 어긋남)
mismatch=""
for f in $agents; do
  base=$(basename "$f" .md)
  nm=$(awk -F': *' 'NR<=8&&/^name:/{print $2;exit}' "$f" 2>/dev/null | tr -d '\r')
  [ "$nm" = "$base" ] || mismatch="$mismatch ${base}(name=${nm:-없음})"
done
[ -z "$mismatch" ] && ok "frontmatter name == 파일명" || no "name/파일명 불일치" "$mismatch"

# ─────────────────────────────────────────────────────────────
section "2. MODEL_MAP 정합성 (단일 진실 소스)"
# ─────────────────────────────────────────────────────────────

DR="project/.claude/hooks/dispatch-ready.sh"
if [ ! -f "$DR" ]; then
  skip "MODEL_MAP 검사" "dispatch-ready.sh 없음"
else
  map_names=$(grep -oE '"[a-z-]+":[[:space:]]*"(sonnet|opus|fable|haiku)"' "$DR" \
              | sed -E 's/^"([a-z-]+)".*/\1/' | sort -u)
  file_names=$(for f in $agents; do basename "$f" .md; done | sort -u)

  only_map=$(comm -23 <(echo "$map_names") <(echo "$file_names"))
  [ -z "$only_map" ] && ok "MODEL_MAP의 모든 에이전트가 실제 파일로 존재" \
                     || no "MODEL_MAP에만 있고 파일 없음 → 스폰 실패" "$(echo $only_map)"

  only_file=$(comm -13 <(echo "$map_names") <(echo "$file_names"))
  [ -z "$only_file" ] && ok "모든 에이전트 파일이 MODEL_MAP에 등록됨" \
                      || no "MODEL_MAP 미등록 → 기본 모델로 폴백" "$(echo $only_file)"
fi

# ─────────────────────────────────────────────────────────────
section "3. secret-guard (2026-07-15: root 비번 5개월 공개 유출)"
# ─────────────────────────────────────────────────────────────

SG="project/.claude/hooks/secret-guard.sh"
if [ ! -f "$SG" ]; then
  no "secret-guard.sh 존재" "파일 없음"
else
  # 정의부만 로드 (INPUT=$(cat) 실행 방지)
  sg_defs=$(awk '/^SECRET_REGEX=/{p=1} p{print} /^}/{if(p&&f)exit} /^scan_text\(\)/{f=1}' "$SG")
  eval "$sg_defs" 2>/dev/null

  if ! type scan_text >/dev/null 2>&1; then
    no "scan_text 로드" "함수 정의를 찾지 못함"
  else
    # 탐지해야 할 것 — 전부 실제 유출/발견 사례
    detect_case() {
      local label="$1" text="$2"
      [ -n "$(printf '%s\n' "$text" | scan_text)" ] \
        && ok "탐지: $label" || no "미탐지: $label" "$text"
    }
    detect_case "Vultr root 비번(특수문자 포함, 실제 유출)" 'SSH_PASSWORD=B6n!o]U@[5P}tL)H'
    detect_case "대문자 변수명 (grep -i 누락 시 뚫림)"       'SSH_PASSWORD=SomePlainPass123'
    detect_case "sshpass 하드코딩"                          "sshpass -p 'B6n!o]U@[5P}tL)H' ssh root@1.2.3.4"
    detect_case "Anthropic 키"                              'ANTHROPIC_API_KEY=sk-ant-api03-abcdefghij1234567890'
    detect_case "Google 키"                                 'GOOGLE_KEY=AIzaSyD1234567890abcdefghij1234567890abc'

    # 통과해야 할 것 — 오탐 시 정상 작업이 막힘
    pass_case() {
      local label="$1" text="$2"
      [ -z "$(printf '%s\n' "$text" | scan_text)" ] \
        && ok "오탐없음: $label" || no "오탐: $label" "$text"
    }
    pass_case "환경변수 참조"   'SSH_PASSWORD="$SSH_PASSWORD"'
    pass_case "커맨드 치환"     'password: $(cat .secret)'
    pass_case "placeholder"     'ANTHROPIC_API_KEY=<YOUR_API_KEY>'
    pass_case "example 값"      'API_KEY=your_key_here'
  fi

  # 파일명 차단 (값 패턴을 빠져나가도 막는 2차 방어선)
  if grep -q "scan_staged_filenames" "$SG"; then
    ok "시크릿 파일명 차단 로직 존재"
  else
    no "파일명 차단 부재" ".deploy_credentials 류를 값 무관하게 막아야 함"
  fi

  # -i 플래그 (오늘 유출의 직접 원인)
  if grep -qE 'grep -[a-z]*i[a-z]*Eo? *"\$SECRET_REGEX"' "$SG"; then
    ok "scan_text에 대소문자 무시(-i) 적용"
  else
    no "scan_text에 -i 없음" "SSH_PASSWORD 등 대문자 변수가 통과함 (2026-07-15 유출 원인)"
  fi
fi

# ─────────────────────────────────────────────────────────────
section "4. 훅 무결성"
# ─────────────────────────────────────────────────────────────

hooks=$(real_files "project/.claude/hooks" "*.sh")
hcount=$(printf '%s\n' "$hooks" | grep -c . | tr -d ' \n')
hcount=${hcount:-0}

syn_bad=""
for f in $hooks; do bash -n "$f" 2>/dev/null || syn_bad="$syn_bad $(basename "$f")"; done
[ -z "$syn_bad" ] && ok "훅 ${hcount}개 bash 문법 정상" || no "훅 문법 오류" "$syn_bad"

# 실행 권한
noexec=""
for f in $hooks; do [ -x "$f" ] || noexec="$noexec $(basename "$f")"; done
[ -z "$noexec" ] && ok "훅 전부 실행 권한 보유" || no "실행 권한 없음" "$noexec"

# ─────────────────────────────────────────────────────────────
section "5. 알려진 미해결 결함 (3·4순위 — 수정 시 이 테스트가 초록불로 전환)"
# ─────────────────────────────────────────────────────────────

# [4순위] 비인용 heredoc = 임의 코드 실행. $RESULT는 LLM 생성물이라 신뢰 불가.
vuln=""
for f in $hooks; do
  grep -qE 'python3 +<< *[A-Z_]+$' "$f" 2>/dev/null && vuln="$vuln $(basename "$f")"
done
if [ -z "$vuln" ]; then
  ok "비인용 heredoc 없음 (RCE 차단)"
else
  no "비인용 heredoc = RCE 경로 ($(echo $vuln | wc -w | tr -d ' ')개)" \
     "<< 'PYEOF' 로 인용 필요:$vuln"
fi

# [3순위] on_fail 도달 경로
# on_fail.sh는 (이슈ID, 에러메시지) 인자가 필요해 Stop hook에 직접 걸 수 없다.
# → on-agent-complete.sh가 좌초(stall)를 감지해 호출하는 것이 올바른 배선이다.
if grep -q "on_fail.sh" project/.claude/hooks/on-agent-complete.sh 2>/dev/null; then
  ok "on_fail.sh 도달 경로 존재 (on-agent-complete의 stall 감지)"
else
  no "on_fail.sh 미배선" "실패 경로 부재 — registry에 retry_count>0가 0건인 이유"
fi

# [3순위] registry 동시성 — Stop 이벤트 동시 발화 훅에 락이 있는가
# flock(1)은 macOS에 없다 → python fcntl (lib/registry_lock.py)
if [ ! -f "project/.claude/hooks/lib/registry_lock.py" ]; then
  no "registry_lock 라이브러리 없음" "동시 쓰기 시 lost update"
else
  ok "registry_lock 라이브러리 존재 (fcntl 기반 원자적 RMW)"
  # Stop/SubagentStop에 동시 등록된 훅 = 실제 경쟁 지점
  unlocked=""
  for h in meta-review on-agent-complete; do
    f="project/.claude/hooks/${h}.sh"
    [ -f "$f" ] || continue
    grep -qE "json\.dump|open\(.*'w'\)" "$f" 2>/dev/null || continue   # 쓰기 없으면 무관
    grep -q "registry_txn\|registry_lock" "$f" 2>/dev/null || unlocked="$unlocked $h"
  done
  [ -z "$unlocked" ] && ok "Stop 동시발화 훅에 락 적용됨" \
                     || no "Stop 동시발화 훅 락 누락" "lost update 위험:$unlocked"
fi

# ─────────────────────────────────────────────────────────────
section "6. 이식성 (2026-06-29~07-15: CI가 2주간 빨간불이었음)"
# ─────────────────────────────────────────────────────────────

# git에 커밋된 절대경로 심링크는 다른 머신/CI에서 깨진 링크가 된다.
# .claude/hooks/*.sh 36개가 /Users/gangseungsig/... 를 가리킨 채 커밋돼 있어
# CI의 bash -n이 "No such file or directory"로 전부 실패했다.
# 로컬에서는 대상이 실재하므로 절대 재현되지 않는다 — 그래서 2주간 몰랐다.
abs_links=$(
  git ls-files -s 2>/dev/null | awk '$1=="120000"{print $4}' | while read -r l; do
    t=$(git cat-file -p ":$l" 2>/dev/null)
    if [ "${t#/Users/}" != "$t" ] || [ "${t#/Volumes/}" != "$t" ] || [ "${t#/home/}" != "$t" ]; then
      printf '%s\n' "$l"
    fi
  done
)
if [ -z "$abs_links" ]; then
  ok "커밋된 절대경로 심링크 없음 (다른 머신·CI에서 이식 가능)"
else
  cnt=$(printf '%s\n' "$abs_links" | grep -c .)
  no "절대경로 심링크 ${cnt}개 커밋됨 → CI에서 깨짐" "$(printf '%s' "$abs_links" | head -2 | tr '\n' ' ')…"
fi

# ─────────────────────────────────────────────────────────────
section "7. registry 스키마"
# ─────────────────────────────────────────────────────────────

REG=".claude/issue-db/registry.json"
if [ ! -f "$REG" ]; then
  skip "registry 검사" "파일 없음"
else
  python3 - "$REG" << 'PY' && ok "registry.json 파싱 + ID 중복 없음" || no "registry 무결성 실패"
import json, sys
from collections import Counter
r = json.load(open(sys.argv[1], encoding='utf-8'))
iss = r.get('issues', [])
dup = [k for k, v in Counter(i.get('id') for i in iss).items() if v > 1 and k]
if dup:
    print(f"      → 중복 ID: {dup[:5]}", file=sys.stderr); sys.exit(1)
sys.exit(0)
PY
fi

# ─────────────────────────────────────────────────────────────
printf '\n\033[1m─────────────────────────────────────\033[0m\n'
printf '  통과 %d / 실패 %d / 건너뜀 %d\n' "$PASS" "$FAIL" "$SKIP"
if [ "$FAIL" -gt 0 ]; then
  printf '\n  \033[31m실패 항목:\033[0m\n'
  for n in "${FAILED_NAMES[@]}"; do printf '    - %s\n' "$n"; done
  printf '\n'
  exit 1
fi
printf '\n  \033[32m전부 통과\033[0m\n\n'
exit 0
