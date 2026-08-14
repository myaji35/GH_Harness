#!/usr/bin/env bash
# detect-project-type.sh
# v5/A1 — 프로젝트 타입 자동 감지 (code / doc / hybrid)
# Phoenix 같은 비즈 문서 워크스페이스에 lint/tsc 트리거가 부적절하게 발동하는 문제 해결.
#
# 사용:
#   bash detect-project-type.sh                # 감지 결과만 stdout (code|doc|hybrid)
#   bash detect-project-type.sh --json         # JSON으로 세부 시그널 출력
#   bash detect-project-type.sh --write        # .claude/project-type.yaml 생성/갱신
#   bash detect-project-type.sh --explain      # 사람이 읽는 설명
#
# 시그널 (현재 디렉터리 기준, .git/node_modules 제외):
#   code 시그널 (+점수): package.json / Gemfile / pyproject.toml / tsconfig.json / go.mod / Cargo.toml / pom.xml /
#                       *.ts, *.tsx, *.py, *.rb, *.go, *.rs, *.java, *.kt 파일 수 > 5
#   doc 시그널 (+점수):  *.md > 5 + *.pdf > 0 + 빌드 시스템 파일 0
#   hybrid: code와 doc 둘 다 강함

set -euo pipefail

MODE="${1:-detect}"  # detect|--json|--write|--explain

ROOT_DIR="$(pwd)"
SCORE_CODE=0
SCORE_DOC=0
SIGNALS_CODE=()
SIGNALS_DOC=()

# --- 빌드 시스템 파일 (code +3씩) ---
for f in package.json Gemfile pyproject.toml tsconfig.json go.mod Cargo.toml pom.xml composer.json deno.json bun.lockb; do
  if [[ -f "$ROOT_DIR/$f" ]]; then
    SCORE_CODE=$((SCORE_CODE+3))
    SIGNALS_CODE+=("$f")
  fi
done

# --- 코드 파일 수 (>5 시 +2, >50 시 +5) ---
CODE_COUNT=$(find "$ROOT_DIR" -maxdepth 4 \
  \( -name "*.ts" -o -name "*.tsx" -o -name "*.py" -o -name "*.rb" \
     -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.kt" \
     -o -name "*.swift" -o -name "*.c" -o -name "*.cpp" \) \
  -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/vendor/*" \
  2>/dev/null | wc -l | tr -d ' ')

if (( CODE_COUNT > 50 )); then
  SCORE_CODE=$((SCORE_CODE+5))
  SIGNALS_CODE+=("source_files_${CODE_COUNT}")
elif (( CODE_COUNT > 15 )); then
  SCORE_CODE=$((SCORE_CODE+3))
  SIGNALS_CODE+=("source_files_${CODE_COUNT}")
elif (( CODE_COUNT > 5 )); then
  SCORE_CODE=$((SCORE_CODE+2))
  SIGNALS_CODE+=("source_files_${CODE_COUNT}")
fi

# --- *.md 파일 수 (>5 시 +2, >15 시 +3) ---
MD_COUNT=$(find "$ROOT_DIR" -maxdepth 3 -name "*.md" \
  -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null | wc -l | tr -d ' ')

if (( MD_COUNT > 15 )); then
  SCORE_DOC=$((SCORE_DOC+3))
  SIGNALS_DOC+=("markdown_${MD_COUNT}")
elif (( MD_COUNT > 5 )); then
  SCORE_DOC=$((SCORE_DOC+2))
  SIGNALS_DOC+=("markdown_${MD_COUNT}")
fi

# --- *.pdf 파일 수 (>0 시 +1) ---
PDF_COUNT=$(find "$ROOT_DIR" -maxdepth 3 -name "*.pdf" \
  -not -path "*/.git/*" 2>/dev/null | wc -l | tr -d ' ')
if (( PDF_COUNT > 0 )); then
  SCORE_DOC=$((SCORE_DOC+1))
  SIGNALS_DOC+=("pdf_${PDF_COUNT}")
fi

# --- 빌드 시스템 부재 보너스 (doc +2) ---
if (( SCORE_CODE == 0 )) && (( MD_COUNT > 3 )); then
  SCORE_DOC=$((SCORE_DOC+2))
  SIGNALS_DOC+=("no_build_system")
fi

# --- 결정 ---
# hybrid: 양쪽 모두 의미있는 시그널 (each ≥ 4)
# code/doc: 더 큰 점수가 임계치 이상이고 차이가 2 이상
PROJECT_TYPE="unknown"
DIFF=$(( SCORE_CODE - SCORE_DOC ))
if (( SCORE_CODE >= 4 && SCORE_DOC >= 4 )); then
  PROJECT_TYPE="hybrid"
elif (( DIFF >= 2 )); then
  PROJECT_TYPE="code"
elif (( DIFF <= -2 )); then
  PROJECT_TYPE="doc"
elif (( SCORE_CODE >= SCORE_DOC && SCORE_CODE > 0 )); then
  PROJECT_TYPE="code"
elif (( SCORE_DOC > 0 )); then
  PROJECT_TYPE="doc"
else
  PROJECT_TYPE="doc"  # 기본값 (아무 시그널도 없으면 안전한 쪽)
fi

# --- 출력 분기 ---
case "$MODE" in
  --json)
    sig_code_json=$(printf '"%s",' "${SIGNALS_CODE[@]:-}" | sed 's/,$//')
    sig_doc_json=$(printf '"%s",' "${SIGNALS_DOC[@]:-}" | sed 's/,$//')
    cat <<JSON
{
  "project_type": "${PROJECT_TYPE}",
  "score_code": ${SCORE_CODE},
  "score_doc": ${SCORE_DOC},
  "signals_code": [${sig_code_json}],
  "signals_doc": [${sig_doc_json}],
  "code_count": ${CODE_COUNT},
  "md_count": ${MD_COUNT},
  "pdf_count": ${PDF_COUNT},
  "detected_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
    ;;
  --write)
    mkdir -p "$ROOT_DIR/.claude"
    cat > "$ROOT_DIR/.claude/project-type.yaml" <<YAML
# Auto-detected by detect-project-type.sh (v5/A1)
# 수동 수정 가능 — manual_override: true 설정 시 자동 재감지 비활성
project_type: ${PROJECT_TYPE}
manual_override: false
detected_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
signals:
  score_code: ${SCORE_CODE}
  score_doc: ${SCORE_DOC}
  code_files: ${CODE_COUNT}
  md_files: ${MD_COUNT}
  pdf_files: ${PDF_COUNT}
# 트리거 매트릭스 적용 (proactive-scan, on_complete 등에서 참조)
triggers:
  tsc_typecheck: $([[ "$PROJECT_TYPE" == "doc" ]] && echo "false" || echo "true")
  eslint: $([[ "$PROJECT_TYPE" == "doc" ]] && echo "false" || echo "true")
  npm_audit: $([[ "$PROJECT_TYPE" == "doc" ]] && echo "false" || echo "true")
  todo_fixme_scan: $([[ "$PROJECT_TYPE" == "doc" ]] && echo "md_only" || echo "all")
  screen_gap_scan: $([[ "$PROJECT_TYPE" == "doc" ]] && echo "false" || echo "true")
  doc_sync_check: $([[ "$PROJECT_TYPE" == "code" ]] && echo "false" || echo "true")
  pdf_verify: $([[ "$PROJECT_TYPE" == "code" ]] && echo "false" || echo "true")
  git_status_scan: true
YAML
    echo ".claude/project-type.yaml 생성/갱신 완료 (type: ${PROJECT_TYPE})"
    ;;
  --explain)
    cat <<EXP
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 프로젝트 타입 감지 결과
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  타입:        ${PROJECT_TYPE}
  코드 점수:   ${SCORE_CODE}
  문서 점수:   ${SCORE_DOC}

  📊 시그널:
    - 빌드 파일 (package.json/Gemfile 등): $((${#SIGNALS_CODE[@]}))
    - 소스 파일 (ts/py/rb 등): ${CODE_COUNT}
    - 마크다운 (.md): ${MD_COUNT}
    - PDF 산출물: ${PDF_COUNT}

  🎯 권장 트리거:
$(if [[ "$PROJECT_TYPE" == "doc" ]]; then
  echo "    ✅ doc_sync_check, pdf_verify, todo_fixme(md only)"
  echo "    ❌ tsc, eslint, npm audit, screen_gap_scan"
elif [[ "$PROJECT_TYPE" == "code" ]]; then
  echo "    ✅ tsc, eslint, npm audit, screen_gap_scan, todo_fixme(all)"
  echo "    ❌ doc_sync_check (선택)"
else
  echo "    ✅ tsc, eslint, doc_sync_check, pdf_verify (둘 다)"
fi)

  ▶ 적용: bash $(basename "$0") --write
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EXP
    ;;
  *)
    echo "${PROJECT_TYPE}"
    ;;
esac
