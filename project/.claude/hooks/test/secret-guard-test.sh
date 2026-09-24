#!/usr/bin/env bash
# secret-guard 차단 테스트. 가드를 수정할 때마다 반드시 돌린다.
#
# 배경 (2026-09-23): 가드의 오탐을 고치려다 정규식을 깨뜨려
# `grep: brackets ([ ]) not balanced` 상태가 됐고, 실제 Google API 키가
# 그대로 통과했다. 백업에서 즉시 복구했지만 테스트가 없어 육안으로만 확인했다.
# 이 테스트는 그 재발을 막는다.
#
# 사용: bash ~/.claude/harness-core/hooks/test/secret-guard-test.sh
# 종료코드 0 = 전체 통과. 그 외 = 실패 건수.

GUARD="$HOME/.claude/harness-core/hooks/secret-guard.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 99
git init -q && git config user.email t@t && git config user.name t

PASS=0; FAIL=0

# $1 = 기대(BLOCK|ALLOW), $2 = 설명, $3 = 파일에 쓸 내용
run() {
  rm -f f.txt
  printf '%s\n' "$3" > f.txt
  git add f.txt 2>/dev/null
  out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | bash "$GUARD" 2>&1)
  if echo "$out" | grep -q "차단"; then got=BLOCK; else got=ALLOW; fi
  if [ "$got" = "$1" ]; then
    PASS=$((PASS+1)); printf "  [OK]   %-32s %s\n" "$2" "$got"
  else
    FAIL=$((FAIL+1)); printf "  [FAIL] %-32s expect %s got %s\n" "$2" "$1" "$got"
  fi
}

echo "=== MUST BLOCK (real secrets) ==="
# 주의: 아래 가짜 키들은 실제 형식의 길이를 정확히 맞춰야 한다.
#   Google = AIza + 35자, AWS = AKIA + 16자.
#   그리고 placeholder 필터(example/your_/xxxx 등)에 걸리는 단어를 쓰면 안 된다.
#   2026-09-23: AWS 공식 예시키 AKIAIOSFODNN7EXAMPLE 를 썼다가 'example' 때문에
#   제외되어 미탐처럼 보였다. 가드가 아니라 테스트가 틀린 것이었다.
run BLOCK "Google API key"  'const k = "AIzaSyD1234567890abcdefghijklmnopqrstuv";'
run BLOCK "OpenAI key"      'const k = "sk-proj1234567890abcdefghijklmn";'
run BLOCK "Anthropic key"   'KEY="sk-ant-api03-abcdefghijklmnopqrstuvwxyz"'
run BLOCK "GitHub PAT"      'ghp_1234567890abcdefghijklmnopqrstuvwxyz'
run BLOCK "AWS key"         'AKIAQ7RTVW3ZPLMN6KDF'
run BLOCK "Meta token"      'T="EAAGm0PX4ZCpsBAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"'
run BLOCK "plain password"  'password = "hunter2secret"'
run BLOCK "plain api_key"   'api_key: "abcdef1234567890xyz"'
run BLOCK "ssh password"    'SSH_PASSWORD="myRootPass123"'

echo ""
echo "=== MUST ALLOW (false positives) ==="
run ALLOW "TS type decl"    'async function f(url: URL, token: string) {}'
run ALLOW "env ref js"      'const OPENAI_API_KEY = process.env.OPENAI_API_KEY;'
run ALLOW "env ref shell"   'OPENAI_API_KEY=${OPENAI_API_KEY}'
run ALLOW "var pass"        'const openai = new OpenAI({ apiKey: OPENAI_API_KEY });'
run ALLOW "docker -e"       '  -e OPENAI_API_KEY="${OPENAI_API_KEY}" \'
run ALLOW "echo label"      'echo "  - OPENAI_API_KEY"'
run ALLOW "python env"      'tok = os.environ["META_TOKEN"]'
run ALLOW "interface field" '  password: string;'
run ALLOW "placeholder"     'API_KEY=<YOUR_API_KEY_HERE>'

echo ""
echo "  PASS $PASS / FAIL $FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "  ALL GREEN"
else
  echo "  RED - do not ship the guard"
fi
exit $FAIL
