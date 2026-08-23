#!/bin/bash

set +e

usage() {
  cat <<'EOF'
사용법: verify-watch.sh [--once|--print|--help]

  --once  검증 명령을 한 번 실행하고 그 종료코드를 반환
  --print 결정된 검증 명령만 출력
  --help  이 도움말을 출력
EOF
}

case "${1:-}" in
  --help)
    usage
    exit 0
    ;;
  --once|--print|"")
    mode="${1:-watch}"
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

project_root="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$project_root" ]; then
  project_root="$PWD"
fi

verify_cmd=""
verify_cmd_file="$project_root/.claude/verify-cmd"

if [ -f "$verify_cmd_file" ]; then
  verify_cmd="$(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$verify_cmd_file" | head -n 1)"
fi

if [ -z "$verify_cmd" ] && [ -f "$project_root/package.json" ]; then
  if command -v node >/dev/null 2>&1 && (
    cd "$project_root" || exit 1
    node -e 'const p=require("./package.json"); process.exit(p.scripts && typeof p.scripts.test === "string" ? 0 : 1)'
  ) >/dev/null 2>&1; then
    verify_cmd="npm test"
  fi
fi

if [ -z "$verify_cmd" ] && [ -f "$project_root/Gemfile" ] && [ -f "$project_root/bin/rails" ]; then
  verify_cmd="bin/rails test"
fi

if [ -z "$verify_cmd" ] && { [ -f "$project_root/pyproject.toml" ] || [ -f "$project_root/pytest.ini" ]; }; then
  verify_cmd="pytest -q"
fi

if [ -z "$verify_cmd" ]; then
  echo "검증 명령을 찾을 수 없다. $project_root/.claude/verify-cmd 에 한 줄로 명령을 적어라. 예: bin/rails test" >&2
  exit 1
fi

if [ "$mode" = "--print" ]; then
  printf '%s\n' "$verify_cmd"
  exit 0
fi

if [ "$mode" = "--once" ]; then
  cd "$project_root" || exit 1
  bash -lc "$verify_cmd"
  exit $?
fi

if ! command -v watchexec >/dev/null 2>&1; then
  echo 'watchexec 미설치: brew install watchexec' >&2
  exit 1
fi

echo "[verify-watch] 감시 시작 — 명령: $verify_cmd (Ctrl+C로 종료)"

cd "$project_root" || exit 1
watchexec \
  --wrap-process=session \
  --restart \
  --debounce 800ms \
  --exts rb,py,ts,tsx,js,jsx,go,rs,erb,vue,svelte,sh \
  --ignore '**/node_modules/**' \
  --ignore '**/.git/**' \
  --ignore '**/.venv/**' \
  --ignore '**/vendor/**' \
  --ignore '**/dist/**' \
  --ignore '**/build/**' \
  --ignore '**/__pycache__/**' \
  --ignore '**/.claude/context-snapshots/**' \
  --ignore '**/tmp/**' \
  --ignore '**/log/**' \
  -- bash -lc "$verify_cmd"

exit $?
