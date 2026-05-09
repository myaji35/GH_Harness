#!/bin/bash
# update-project-state.sh — project-state.md 자동 갱신
#
# 호출 시점:
#   1. post-code-change.sh 내부에서 Edit/Write 후
#   2. on_complete.sh 내부에서 이슈 완료 시
#   3. 수동: bash .claude/hooks/update-project-state.sh "decision text"
#
# 동작:
#   - project-state.md가 없으면 템플릿으로 생성
#   - 최근 7일 git log / 현재 READY 이슈 / 최근 변경 파일을 자동 갱신
#   - 1번째 인자가 있으면 "최근 결정사항" 섹션에 날짜와 함께 prepend

set -e

STATE_FILE="project-state.md"
REGISTRY=".claude/issue-db/registry.json"
DECISION="${1:-}"
TODAY="$(date +%Y-%m-%d)"
NOW="$(date +%Y-%m-%d' '%H:%M)"

# 템플릿 부트스트랩
if [ ! -f "$STATE_FILE" ]; then
  PROJECT_NAME="$(basename "$PWD")"
  cat > "$STATE_FILE" << TPL
# Project State — $PROJECT_NAME

> 이 파일은 SessionStart에 자동 로드됩니다. 프로젝트의 살아있는 맥락입니다.
> Harness hook이 자동 갱신하며, 수동 편집도 허용됩니다.

## 1. 지금 만들고 있는 것
<!-- 한 문장으로. 대표님이 직접 작성하거나 product-manager가 갱신 -->
_(아직 정의되지 않음 — 'harness 시작'으로 FEATURE_PLAN을 만들어 주세요)_

## 2. 최근 결정사항 (최신순, 최대 20개)
<!-- DECISIONS_BEGIN -->
<!-- DECISIONS_END -->

## 3. 미해결 질문
<!-- OPEN_QUESTIONS_BEGIN -->
- _(없음)_
<!-- OPEN_QUESTIONS_END -->

## 4. 다음 마일스톤
<!-- MILESTONES_BEGIN -->
- _(미정)_
<!-- MILESTONES_END -->

## 5. 최근 변경 이력 (git log, 자동 갱신)
<!-- GITLOG_BEGIN -->
<!-- GITLOG_END -->

## 6. 살아있는 이슈 (READY/IN_PROGRESS, 자동 갱신)
<!-- ISSUES_BEGIN -->
<!-- ISSUES_END -->

---
_마지막 갱신: (자동)_
TPL
  echo "[project-state] 템플릿 생성: $STATE_FILE"
fi

python3 << PYEOF
import json, subprocess, re, datetime, pathlib, os

STATE = pathlib.Path("$STATE_FILE")
REG = pathlib.Path("$REGISTRY")
DECISION = """$DECISION""".strip()
NOW = "$NOW"
TODAY = "$TODAY"

text = STATE.read_text()

def replace_block(txt, begin, end, content):
    pattern = re.compile(rf"<!-- {begin} -->.*?<!-- {end} -->", re.DOTALL)
    block = f"<!-- {begin} -->\n{content.rstrip()}\n<!-- {end} -->"
    return pattern.sub(block, txt)

# ── (1) 결정사항 prepend ─────────────────────────
if DECISION:
    m = re.search(r"<!-- DECISIONS_BEGIN -->(.*?)<!-- DECISIONS_END -->", text, re.DOTALL)
    existing = m.group(1).strip() if m else ""
    new_entry = f"- **{NOW}** — {DECISION}"
    lines = [new_entry]
    if existing:
        lines += [l for l in existing.splitlines() if l.strip()]
    lines = lines[:20]
    text = replace_block(text, "DECISIONS_BEGIN", "DECISIONS_END", "\n".join(lines))

# ── (2) git log 최근 7일 ─────────────────────────
try:
    log = subprocess.run(
        ["git", "log", "--since=7.days.ago", "--pretty=format:- %ad %s", "--date=short"],
        capture_output=True, text=True, timeout=5
    ).stdout.strip()
    if not log:
        log = "- _(7일간 커밋 없음)_"
    text = replace_block(text, "GITLOG_BEGIN", "GITLOG_END", log[:3000])
except Exception:
    pass

# ── (3) 살아있는 이슈 ─────────────────────────
if REG.exists():
    try:
        r = json.loads(REG.read_text())
        alive = [i for i in r.get("issues", []) if i.get("status") in ("READY", "IN_PROGRESS")]
        if alive:
            lines = [f"- **[{i['status']}]** {i['id']} ({i.get('type','?')}) [{i.get('priority','P?')}] — {i.get('title','')}" for i in alive[:15]]
            block = "\n".join(lines)
            if len(alive) > 15:
                block += f"\n- _... 외 {len(alive)-15}개_"
        else:
            block = "- _(살아있는 이슈 없음 — 새 기획 필요)_"
        text = replace_block(text, "ISSUES_BEGIN", "ISSUES_END", block)
    except Exception:
        pass

# ── 마지막 갱신 시각 ─────────────────────────
text = re.sub(r"_마지막 갱신:.*?_", f"_마지막 갱신: {NOW}_", text)

STATE.write_text(text)
print(f"[project-state] 갱신 완료 ({NOW})")
PYEOF
