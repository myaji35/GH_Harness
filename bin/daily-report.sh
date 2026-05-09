#!/bin/bash
# Daily Report Generator
# 한국시간 기준 09:00~20:00 활동을 분석하여 18:00에 PDF 레포트 생성
# 일요일은 launchd가 자동으로 제외 (Weekday 1-6)

set -uo pipefail

# ──────────────────────────────────────────
# 설정
# ──────────────────────────────────────────
export TZ="Asia/Seoul"
export PATH="/Users/gangseungsig/.rbenv/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

ROOT="/Volumes/E_SSD/02_GitHub.nosync"
HARNESS_DIR="${ROOT}/GH_Harness"
REPORT_DIR="${HARNESS_DIR}/Report"
TODAY="$(date +%Y%m%d)"
TODAY_HUMAN="$(date +"%Y년 %m월 %d일 %A")"
ISO_TODAY="$(date +%Y-%m-%d)"
TITLE="일일활동보고서"
PDF_PATH="${REPORT_DIR}/${TODAY}_${TITLE}.pdf"
HTML_PATH="/tmp/${TODAY}_${TITLE}.html"
LOG_PATH="${REPORT_DIR}/.daily-report.log"

mkdir -p "$REPORT_DIR"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] daily-report 시작" >> "$LOG_PATH"

# 일요일 가드 (launchd가 막지만 수동 실행 보호)
DOW=$(date +%u)  # 1=월 ... 7=일
if [[ "$DOW" == "7" && "${1:-}" != "--force" ]]; then
  echo "[skip] 일요일 — 레포트 생성 건너뜀 (--force로 강제 실행 가능)" | tee -a "$LOG_PATH"
  exit 0
fi

# ──────────────────────────────────────────
# 1. 프로젝트 목록 수집 (00XX_*)
# ──────────────────────────────────────────
PROJECTS=()
while IFS= read -r dir; do
  PROJECTS+=("$dir")
done < <(find "$ROOT" -maxdepth 1 -type d -name "00[0-9][0-9]_*" 2>/dev/null | sort)

PROJECTS+=("$HARNESS_DIR")  # GH_Harness 자체도 포함

# ──────────────────────────────────────────
# 2. 데이터 수집 함수
# ──────────────────────────────────────────
collect_git_activity() {
  local dir="$1"
  local name="$(basename "$dir")"
  local since="${ISO_TODAY} 00:00:00"
  local until="${ISO_TODAY} 23:59:59"

  if [[ ! -d "$dir/.git" ]]; then
    echo ""
    return
  fi

  local commits
  commits=$(cd "$dir" && git log --since="$since" --until="$until" --pretty=format:"- [%h] %s (%an, %ar)" 2>/dev/null || true)

  if [[ -z "$commits" ]]; then
    echo ""
  else
    echo "$commits"
  fi
}

collect_md_changes() {
  local dir="$1"
  if [[ ! -d "$dir/.git" ]]; then
    echo ""
    return
  fi

  local since="${ISO_TODAY} 00:00:00"
  # 오늘 변경된 .md 파일 + 변경 라인 수
  (cd "$dir" && git log --since="$since" --name-only --pretty=format:"" -- '*.md' 2>/dev/null \
    | sort -u | grep -v '^$' || true)
}

collect_md_diff_summary() {
  local dir="$1"
  local file="$2"
  if [[ ! -f "$dir/$file" ]]; then return; fi

  local since="${ISO_TODAY} 00:00:00"
  (cd "$dir" && git log --since="$since" --pretty=format:"%h" -- "$file" 2>/dev/null | head -5)
}

collect_issues() {
  local dir="$1"
  local registry="$dir/.claude/issue-db/registry.json"
  if [[ ! -f "$registry" ]]; then
    echo ""
    return
  fi

  # 오늘 생성/완료된 이슈 추출
  /usr/bin/python3 - "$registry" "$ISO_TODAY" <<'PYEOF' 2>/dev/null || echo ""
import json, sys, re
path, today = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        data = json.load(f)
    issues = data.get("issues", [])
    today_issues = []
    for it in issues:
        created = it.get("created_at", "")
        updated = it.get("updated_at", "")
        completed = it.get("completed_at", "")
        if today in (created or "") or today in (updated or "") or today in (completed or ""):
            today_issues.append(it)
    if not today_issues:
        sys.exit(0)
    for it in today_issues:
        iid = it.get("id", "?")
        typ = it.get("type", "?")
        prio = it.get("priority", "?")
        status = it.get("status", "?")
        title = it.get("title", "") or it.get("payload", {}).get("title", "")
        result = it.get("result", {})
        summary = ""
        if isinstance(result, dict):
            summary = result.get("summary", "") or json.dumps(result, ensure_ascii=False)[:200]
        print(f"- **{iid}** [{prio}/{status}] `{typ}` — {title}")
        if summary and status in ("DONE", "COMPLETED"):
            print(f"  - 해결: {summary[:300]}")
PYEOF
}

# ──────────────────────────────────────────
# 3. 마크다운 본문 빌드
# ──────────────────────────────────────────
MD_BODY=""
TOTAL_COMMITS=0
TOTAL_ISSUES=0
TOTAL_MD_CHANGES=0
PROJECTS_WITH_ACTIVITY=()

for proj in "${PROJECTS[@]}"; do
  pname="$(basename "$proj")"
  commits=$(collect_git_activity "$proj")
  issues=$(collect_issues "$proj")
  md_changes=$(collect_md_changes "$proj")

  if [[ -z "$commits" && -z "$issues" && -z "$md_changes" ]]; then
    continue
  fi

  PROJECTS_WITH_ACTIVITY+=("$pname")
  MD_BODY+="\n## 📁 ${pname}\n\n"

  # 커밋
  if [[ -n "$commits" ]]; then
    cnt=$(echo "$commits" | grep -c "^- " || echo 0)
    TOTAL_COMMITS=$((TOTAL_COMMITS + cnt))
    MD_BODY+="### 커밋 (${cnt}건)\n\n${commits}\n\n"
  fi

  # 이슈
  if [[ -n "$issues" ]]; then
    cnt=$(echo "$issues" | grep -c "^- " || echo 0)
    TOTAL_ISSUES=$((TOTAL_ISSUES + cnt))
    MD_BODY+="### 이슈 (${cnt}건)\n\n${issues}\n\n"
  fi

  # 변경된 .md 파일
  if [[ -n "$md_changes" ]]; then
    cnt=$(echo "$md_changes" | wc -l | tr -d ' ')
    TOTAL_MD_CHANGES=$((TOTAL_MD_CHANGES + cnt))
    MD_BODY+="### 업데이트된 문서 (.md, ${cnt}개)\n\n"
    while IFS= read -r mdfile; do
      [[ -z "$mdfile" ]] && continue
      MD_BODY+="- \`${mdfile}\`"
      hashes=$(collect_md_diff_summary "$proj" "$mdfile")
      if [[ -n "$hashes" ]]; then
        MD_BODY+=" (커밋: $(echo $hashes | tr '\n' ' '))"
      fi
      MD_BODY+="\n"
    done <<< "$md_changes"
    MD_BODY+="\n"
  fi
done

# ──────────────────────────────────────────
# 4. GH_Harness 차원의 반성 (전역)
# ──────────────────────────────────────────
HARNESS_REFLECTION=""

# 글로벌 .md 변경
GLOBAL_CHANGES=$(cd "$HARNESS_DIR" && git log --since="${ISO_TODAY} 00:00:00" --name-only --pretty=format:"" -- 'global/**/*.md' '*.md' 'docs/**/*.md' 2>/dev/null | sort -u | grep -v '^$' || true)

if [[ -n "$GLOBAL_CHANGES" ]]; then
  HARNESS_REFLECTION+="### 전역 규칙/문서 변경\n\n"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    HARNESS_REFLECTION+="- \`${f}\`\n"
  done <<< "$GLOBAL_CHANGES"
  HARNESS_REFLECTION+="\n"
fi

# 프로젝트별 CLAUDE.md 변경 감지
PROJECT_CLAUDE_MD=""
for proj in "${PROJECTS[@]}"; do
  pname="$(basename "$proj")"
  if [[ -d "$proj/.git" ]]; then
    changes=$(cd "$proj" && git log --since="${ISO_TODAY} 00:00:00" --name-only --pretty=format:"" -- 'CLAUDE.md' '.claude/**/*.md' 2>/dev/null | sort -u | grep -v '^$' || true)
    if [[ -n "$changes" ]]; then
      PROJECT_CLAUDE_MD+="**${pname}**:\n"
      while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        PROJECT_CLAUDE_MD+="- \`${f}\`\n"
      done <<< "$changes"
      PROJECT_CLAUDE_MD+="\n"
    fi
  fi
done

if [[ -n "$PROJECT_CLAUDE_MD" ]]; then
  HARNESS_REFLECTION+="### 프로젝트별 Claude 규칙 변경\n\n${PROJECT_CLAUDE_MD}"
fi

# 반성 거리 자동 추출 (FAIL/REGRESSION/REPEAT_FAIL 이슈)
LESSONS=""
for proj in "${PROJECTS[@]}"; do
  registry="$proj/.claude/issue-db/registry.json"
  [[ ! -f "$registry" ]] && continue
  fails=$(/usr/bin/python3 - "$registry" "$ISO_TODAY" <<'PYEOF' 2>/dev/null || true
import json, sys
path, today = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        data = json.load(f)
    for it in data.get("issues", []):
        upd = it.get("updated_at", "") or ""
        if today not in upd:
            continue
        typ = it.get("type", "")
        status = it.get("status", "")
        if "FAIL" in typ or "REGRESSION" in typ or "REPEAT" in typ or status == "FAILED":
            print(f"- [{it.get('id','?')}] {typ}/{status}: {it.get('title','')}")
except: pass
PYEOF
)
  if [[ -n "$fails" ]]; then
    pname="$(basename "$proj")"
    LESSONS+="**${pname}**:\n${fails}\n\n"
  fi
done

if [[ -n "$LESSONS" ]]; then
  HARNESS_REFLECTION+="### 실패/회귀 이슈 (반성 거리)\n\n${LESSONS}"
fi

if [[ -z "$HARNESS_REFLECTION" ]]; then
  HARNESS_REFLECTION="오늘 GH_Harness 차원의 규칙 변경 또는 반성 거리는 기록되지 않았습니다.\n\n"
fi

# ──────────────────────────────────────────
# 5. 활동 시간대 분석 (09:00~20:00)
# ──────────────────────────────────────────
TIME_DIST=""
for proj in "${PROJECTS[@]}"; do
  if [[ ! -d "$proj/.git" ]]; then continue; fi
  hours=$(cd "$proj" && git log --since="${ISO_TODAY} 09:00:00" --until="${ISO_TODAY} 20:00:00" --pretty=format:"%cd" --date=format:"%H" 2>/dev/null || true)
  if [[ -n "$hours" ]]; then
    while IFS= read -r h; do
      [[ -z "$h" ]] && continue
      TIME_DIST+="$h\n"
    done <<< "$hours"
  fi
done

HOUR_BAR=""
if [[ -n "$TIME_DIST" ]]; then
  for h in 09 10 11 12 13 14 15 16 17 18 19 20; do
    cnt=$(printf "%s" "$TIME_DIST" | grep -c "^${h}$" 2>/dev/null | head -1)
    cnt="${cnt//[^0-9]/}"
    [[ -z "$cnt" ]] && cnt=0
    bar=""
    capped=$cnt
    [[ $capped -gt 30 ]] && capped=30
    for ((i=0; i<capped; i++)); do bar+="█"; done
    HOUR_BAR+="${h}:00  ${bar} ${cnt}\n"
  done
fi

# ──────────────────────────────────────────
# 6. 마크다운 → HTML
# ──────────────────────────────────────────
NUM_PROJECTS=${#PROJECTS_WITH_ACTIVITY[@]}

if [[ -z "$MD_BODY" ]]; then
  MD_BODY="\n오늘은 활동이 기록되지 않았습니다.\n\n각 프로젝트의 git 커밋, .claude/issue-db/registry.json, 변경된 .md 파일을 분석한 결과 활동 데이터가 없습니다.\n"
fi

cat > "$HTML_PATH" <<HTMLEOF
<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<title>${TITLE} ${TODAY}</title>
<style>
  @page { size: A4; margin: 12mm 14mm; }
  html, body { margin: 0; padding: 0; }
  body { font-family: "Apple SD Gothic Neo", "Helvetica Neue", sans-serif;
         color: #16325C; line-height: 1.45; font-size: 10pt; }
  .header-bar { display: flex; justify-content: space-between; align-items: baseline;
                border-bottom: 2px solid #00A1E0; padding-bottom: 3mm; margin-bottom: 5mm; }
  .header-bar .title { font-size: 18pt; color: #00A1E0; font-weight: 700; }
  .header-bar .meta { font-size: 9pt; color: #54698D; text-align: right; }
  h1 { font-size: 13pt; color: #00A1E0; margin: 6mm 0 2mm;
       border-bottom: 1px solid #D8DDE6; padding-bottom: 1.5mm; }
  h1:first-of-type { margin-top: 0; }
  h2 { font-size: 11.5pt; color: #16325C; margin: 4mm 0 1.5mm; padding-left: 2.5mm;
       border-left: 3px solid #00A1E0; }
  h3 { font-size: 10pt; color: #54698D; margin: 2.5mm 0 1mm; font-weight: 600; }
  p { margin: 1mm 0; }
  .summary-grid { display: table; width: 100%; background: #F3F2F2;
                  border-radius: 3px; margin: 2mm 0 3mm; padding: 2mm 0; }
  .summary-grid .cell { display: table-cell; text-align: center; padding: 1.5mm 2mm;
                        border-right: 1px solid #E5E5E5; }
  .summary-grid .cell:last-child { border-right: none; }
  .summary-grid .label { font-size: 8.5pt; color: #54698D; }
  .summary-grid .value { font-size: 14pt; color: #00A1E0; font-weight: 700; line-height: 1.1; }
  ul { margin: 1mm 0 2mm 4mm; padding: 0; }
  li { margin: 0.3mm 0; }
  code { background: #F3F2F2; padding: 0.3mm 1mm; border-radius: 2px;
         font-family: "SF Mono", monospace; font-size: 9pt; color: #16325C; }
  .reflection { background: #FFF4E6; border-left: 3px solid #FE9339;
                padding: 2.5mm 4mm; border-radius: 0 3px 3px 0; margin: 2mm 0; }
  .reflection h3 { margin-top: 1.5mm; }
  .reflection ul { margin-bottom: 1mm; }
  .timebar { font-family: "SF Mono", monospace; font-size: 8.5pt;
             white-space: pre; background: #F3F2F2; padding: 2.5mm 4mm;
             border-radius: 3px; line-height: 1.3; margin: 2mm 0; }
</style>
</head>
<body>

<div class="header-bar">
  <div class="title">${TITLE}</div>
  <div class="meta">${TODAY_HUMAN} · 09:00–20:00 KST<br>Gagahoho, Inc. · Self-Evolving Harness System</div>
</div>

<h1>요약</h1>
<div class="summary-grid">
  <div class="cell"><div class="value">${NUM_PROJECTS}</div><div class="label">활동 프로젝트</div></div>
  <div class="cell"><div class="value">${TOTAL_COMMITS}</div><div class="label">커밋</div></div>
  <div class="cell"><div class="value">${TOTAL_ISSUES}</div><div class="label">처리 이슈</div></div>
  <div class="cell"><div class="value">${TOTAL_MD_CHANGES}</div><div class="label">.md 변경</div></div>
</div>

<h1>시간대별 활동 (09:00–20:00)</h1>
<div class="timebar">$(echo -e "${HOUR_BAR:-활동 없음}")</div>

<h1>프로젝트별 활동 상세</h1>
$(echo -e "$MD_BODY" | /usr/bin/python3 -c '
import sys, re, html
text = sys.stdin.read()
out = []
for line in text.split("\n"):
    s = line.rstrip()
    if not s:
        out.append("")
        continue
    if s.startswith("## "):
        out.append(f"<h2>{html.escape(s[3:])}</h2>")
    elif s.startswith("### "):
        out.append(f"<h3>{html.escape(s[4:])}</h3>")
    elif s.startswith("- "):
        body = s[2:]
        body = re.sub(r"`([^`]+)`", r"<code>\1</code>", body)
        body = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", body)
        out.append(f"<li>{body}</li>")
    elif s.startswith("  - "):
        body = s[4:]
        body = re.sub(r"`([^`]+)`", r"<code>\1</code>", body)
        out.append(f"<li style=\"margin-left:5mm\">{body}</li>")
    else:
        out.append(f"<p>{html.escape(s)}</p>")
result = []
in_ul = False
for line in out:
    if line.startswith("<li"):
        if not in_ul:
            result.append("<ul>"); in_ul = True
        result.append(line)
    else:
        if in_ul:
            result.append("</ul>"); in_ul = False
        result.append(line)
if in_ul: result.append("</ul>")
print("\n".join(result))
')

<h1>GH_Harness 차원의 반성</h1>
<div class="reflection">
$(echo -e "$HARNESS_REFLECTION" | /usr/bin/python3 -c '
import sys, re, html
text = sys.stdin.read()
out = []
for line in text.split("\n"):
    s = line.rstrip()
    if not s:
        out.append("")
        continue
    if s.startswith("### "):
        out.append(f"<h3>{html.escape(s[4:])}</h3>")
    elif s.startswith("- "):
        body = s[2:]
        body = re.sub(r"`([^`]+)`", r"<code>\1</code>", body)
        body = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", body)
        out.append(f"<li>{body}</li>")
    else:
        body = s
        body = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", body)
        body = re.sub(r"`([^`]+)`", r"<code>\1</code>", body)
        out.append(f"<p>{body}</p>")
result = []
in_ul = False
for line in out:
    if line.startswith("<li"):
        if not in_ul:
            result.append("<ul>"); in_ul = True
        result.append(line)
    else:
        if in_ul:
            result.append("</ul>"); in_ul = False
        result.append(line)
if in_ul: result.append("</ul>")
print("\n".join(result))
')
</div>

</body>
</html>
HTMLEOF

# ──────────────────────────────────────────
# 7. PDF 변환
# ──────────────────────────────────────────
wkhtmltopdf \
  --enable-local-file-access \
  --encoding UTF-8 \
  --margin-top 12mm --margin-bottom 12mm \
  --margin-left 14mm --margin-right 14mm \
  --footer-center "[page]/[topage]" \
  --footer-font-size 7 \
  --footer-font-name "Apple SD Gothic Neo" \
  --footer-spacing 3 \
  "$HTML_PATH" "$PDF_PATH" >> "$LOG_PATH" 2>&1

if [[ -f "$PDF_PATH" ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] PDF 생성 성공: $PDF_PATH" | tee -a "$LOG_PATH"
  # 대화형 세션이면 미리보기 열기
  if [[ "${OPEN_AFTER:-1}" == "1" && -t 1 ]]; then
    open "$PDF_PATH"
  fi
  exit 0
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] PDF 생성 실패" | tee -a "$LOG_PATH"
  exit 1
fi
