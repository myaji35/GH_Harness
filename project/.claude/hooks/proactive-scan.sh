#!/bin/bash
# proactive-scan.sh — 능동적 코드베이스 스캔
# 이슈가 없을 때 자동으로 코드베이스를 스캔하여 새 이슈를 발견한다.
# session-resume.sh에서 "이슈 없음" 상태일 때 호출됨.
# 또는 대표님이 "점검해", "확인해봐", "상태 보여줘" 등 요청 시 호출.
#
# 스캔 항목:
#   1. git diff → 미커밋 변경 리뷰 이슈
#   2. 타입체크/린트 → FIX_BUG 이슈
#   3. TODO/FIXME → 코드 스멜 이슈
#   4. 미사용 의존성 → DEAD_CODE 이슈
#   5. 보안 취약점 (npm audit) → SECURITY 이슈

REGISTRY=".claude/issue-db/registry.json"

if [ ! -f "$REGISTRY" ]; then
  echo "[ProactiveScan] registry.json 없음 — 스캔 스킵"
  exit 0
fi

python3 << 'PYEOF'
import json, subprocess, os, sys, datetime

REGISTRY = ".claude/issue-db/registry.json"

try:
    with open(REGISTRY, 'r') as f:
        registry = json.load(f)
except:
    print("[ProactiveScan] registry.json 읽기 실패")
    sys.exit(0)

# ── 백로그 과다 시 스캔 스킵 (이슈 폭발 방지) ──────────
pending_ready = sum(1 for i in registry.get("issues", []) if i.get("status") == "READY")
if pending_ready > 10:
    print(f"[ProactiveScan] 백로그 {pending_ready}개 과다 — 스캔 스킵 (READY < 10 이하일 때 재개)")
    sys.exit(0)

# 오늘 이미 스캔을 많이 돌렸으면 스킵
today = datetime.date.today().isoformat()
scan_state = registry.setdefault("proactive_scan_state", {"date": today, "count": 0})
if scan_state.get("date") != today:
    scan_state.update({"date": today, "count": 0})
if scan_state["count"] >= 5:
    print(f"[ProactiveScan] 일일 스캔 한도 초과 ({scan_state['count']}/5) — 스킵")
    sys.exit(0)
scan_state["count"] += 1

findings = []
scan_results = {}

# ── 1. git diff 체크 ────────────────────────────────
try:
    diff = subprocess.run(["git", "diff", "--stat"], capture_output=True, text=True, timeout=10)
    diff_staged = subprocess.run(["git", "diff", "--staged", "--stat"], capture_output=True, text=True, timeout=10)
    combined = (diff.stdout or "") + (diff_staged.stdout or "")
    if combined.strip():
        lines = [l for l in combined.strip().split("\n") if l.strip()]
        file_count = len([l for l in lines if "|" in l])
        scan_results["uncommitted_changes"] = file_count
        if file_count > 0:
            findings.append({
                "type": "CODE_SMELL",
                "priority": "P2" if file_count < 10 else "P1",
                "title": f"미커밋 변경 {file_count}개 파일 — 리뷰 필요",
                "assign_to": "code-quality",
                "detail": f"git diff에서 {file_count}개 파일 변경 감지"
            })
except:
    pass

# ── 2. 타입체크 (TypeScript) ────────────────────────
if os.path.exists("tsconfig.json"):
    try:
        tsc = subprocess.run(["npx", "tsc", "--noEmit", "--pretty", "false"],
                           capture_output=True, text=True, timeout=60)
        if tsc.returncode != 0:
            errors = [l for l in tsc.stdout.split("\n") if "error TS" in l]
            error_count = len(errors)
            scan_results["type_errors"] = error_count
            if error_count > 0:
                findings.append({
                    "type": "LINT_CHECK",
                    "priority": "P0",
                    "title": f"TypeScript 타입 에러 {error_count}개",
                    "assign_to": "code-quality",
                    "detail": "\n".join(errors[:5])
                })
        else:
            scan_results["type_errors"] = 0
    except:
        pass

# ── 3. lint (ESLint) ────────────────────────────────
if os.path.exists(".eslintrc.json") or os.path.exists("eslint.config.js") or os.path.exists("eslint.config.mjs"):
    try:
        lint = subprocess.run(["npx", "eslint", ".", "--ext", ".ts,.tsx,.js,.jsx", "--format", "compact", "--quiet"],
                            capture_output=True, text=True, timeout=60)
        if lint.stdout.strip():
            lint_errors = [l for l in lint.stdout.split("\n") if l.strip() and "Error" in l]
            scan_results["lint_errors"] = len(lint_errors)
            if len(lint_errors) > 5:
                findings.append({
                    "type": "LINT_CHECK",
                    "priority": "P1",
                    "title": f"ESLint 에러 {len(lint_errors)}개",
                    "assign_to": "code-quality",
                    "detail": "\n".join(lint_errors[:5])
                })
    except:
        pass

# ── 4. TODO/FIXME/HACK 스캔 ────────────────────────
try:
    todo = subprocess.run(["grep", "-rn", "--include=*.ts", "--include=*.tsx", "--include=*.js",
                          "--include=*.jsx", "--include=*.py", "--include=*.rb",
                          "-E", "TODO|FIXME|HACK|XXX", ".",
                          "--exclude-dir=node_modules", "--exclude-dir=.next",
                          "--exclude-dir=vendor", "--exclude-dir=.git"],
                        capture_output=True, text=True, timeout=15)
    if todo.stdout.strip():
        todo_lines = [l for l in todo.stdout.split("\n") if l.strip()]
        scan_results["todo_count"] = len(todo_lines)
        if len(todo_lines) > 3:
            findings.append({
                "type": "CODE_SMELL",
                "priority": "P3",
                "title": f"TODO/FIXME 코멘트 {len(todo_lines)}개 발견",
                "assign_to": "code-quality",
                "detail": "\n".join(todo_lines[:5])
            })
    else:
        scan_results["todo_count"] = 0
except:
    pass

# ── 5. npm audit (보안) ─────────────────────────────
if os.path.exists("package-lock.json"):
    try:
        audit = subprocess.run(["npm", "audit", "--json"], capture_output=True, text=True, timeout=30)
        audit_data = json.loads(audit.stdout) if audit.stdout else {}
        vulns = audit_data.get("metadata", {}).get("vulnerabilities", {})
        critical = vulns.get("critical", 0) + vulns.get("high", 0)
        scan_results["security_vulns"] = critical
        if critical > 0:
            findings.append({
                "type": "LINT_CHECK",
                "priority": "P0",
                "title": f"보안 취약점 {critical}개 (critical/high)",
                "assign_to": "code-quality",
                "detail": f"npm audit: critical={vulns.get('critical',0)}, high={vulns.get('high',0)}"
            })
    except:
        pass

# ── 6. Gemfile (Ruby) ───────────────────────────────
if os.path.exists("Gemfile"):
    try:
        rubocop = subprocess.run(["bundle", "exec", "rubocop", "--format", "simple", "--no-color"],
                                capture_output=True, text=True, timeout=60)
        if rubocop.returncode != 0:
            offense_lines = [l for l in rubocop.stdout.split("\n") if "offense" in l.lower()]
            scan_results["rubocop_offenses"] = len(offense_lines)
    except:
        pass

# ── 7. 브라우저 콘솔 에러 패턴 스캔 (정적 분석) ────
try:
    # console.error / console.warn 잔재 (프로덕션 코드에 남아있으면 문제)
    console_err = subprocess.run(["grep", "-rn",
                          "--include=*.ts", "--include=*.tsx", "--include=*.js", "--include=*.jsx",
                          "-E", r"console\.(error|warn)\(",  ".",
                          "--exclude-dir=node_modules", "--exclude-dir=.next",
                          "--exclude-dir=dist", "--exclude-dir=build",
                          "--exclude-dir=.git", "--exclude-dir=__tests__",
                          "--exclude-dir=test", "--exclude-dir=tests",
                          "--exclude=*.test.*", "--exclude=*.spec.*"],
                        capture_output=True, text=True, timeout=15)
    console_lines = [l for l in (console_err.stdout or "").split("\n") if l.strip()]
    scan_results["console_error_warn"] = len(console_lines)
    if len(console_lines) > 5:
        findings.append({
            "type": "CODE_SMELL",
            "priority": "P2",
            "title": f"console.error/warn 잔재 {len(console_lines)}개 — 프로덕션 코드 정리 필요",
            "assign_to": "code-quality",
            "detail": "\n".join(console_lines[:5])
        })

    # 미처리 에러: catch 블록이 비어있거나 console.log만 있는 패턴
    empty_catch = subprocess.run(["grep", "-rn",
                          "--include=*.ts", "--include=*.tsx", "--include=*.js", "--include=*.jsx",
                          "-E", r"catch\s*\([^)]*\)\s*\{\s*\}",  ".",
                          "--exclude-dir=node_modules", "--exclude-dir=.next",
                          "--exclude-dir=dist", "--exclude-dir=.git"],
                        capture_output=True, text=True, timeout=15)
    empty_catch_lines = [l for l in (empty_catch.stdout or "").split("\n") if l.strip()]
    scan_results["empty_catch"] = len(empty_catch_lines)
    if len(empty_catch_lines) > 0:
        findings.append({
            "type": "CODE_SMELL",
            "priority": "P1",
            "title": f"빈 catch 블록 {len(empty_catch_lines)}개 — 에러 삼킴 위험",
            "assign_to": "code-quality",
            "detail": "\n".join(empty_catch_lines[:5])
        })

    # window.onerror / addEventListener('error') 없이 unhandled rejection 위험
    if os.path.exists("src") or os.path.exists("app"):
        unhandled = subprocess.run(["grep", "-rn",
                          "--include=*.ts", "--include=*.tsx", "--include=*.js", "--include=*.jsx",
                          "-E", r"throw\s+new\s+Error|Promise\.reject|reject\(",  ".",
                          "--exclude-dir=node_modules", "--exclude-dir=.next",
                          "--exclude-dir=dist", "--exclude-dir=.git"],
                        capture_output=True, text=True, timeout=15)
        throw_lines = [l for l in (unhandled.stdout or "").split("\n") if l.strip()]
        # Error boundary 존재 여부 체크
        err_boundary = subprocess.run(["grep", "-rl",
                          "--include=*.ts", "--include=*.tsx", "--include=*.js", "--include=*.jsx",
                          "-E", r"ErrorBoundary|error\.tsx|componentDidCatch|onError",  ".",
                          "--exclude-dir=node_modules", "--exclude-dir=.next"],
                        capture_output=True, text=True, timeout=10)
        has_boundary = bool(err_boundary.stdout.strip())
        scan_results["throw_count"] = len(throw_lines)
        scan_results["error_boundary"] = has_boundary
        if len(throw_lines) > 3 and not has_boundary:
            findings.append({
                "type": "CODE_SMELL",
                "priority": "P2",
                "title": f"throw/reject {len(throw_lines)}개인데 ErrorBoundary 없음 — 미처리 에러 위험",
                "assign_to": "code-quality",
                "detail": "ErrorBoundary 또는 글로벌 에러 핸들러 추가 권장"
            })

    # .next 빌드 에러 로그 스캔
    next_log = None
    for log_path in [".next/trace", ".next/build-error.log"]:
        if os.path.exists(log_path):
            next_log = log_path
            break
    if next_log:
        try:
            with open(next_log, 'r') as f:
                content = f.read()
            if "error" in content.lower():
                scan_results["next_build_errors"] = True
                findings.append({
                    "type": "LINT_CHECK",
                    "priority": "P0",
                    "title": f"Next.js 빌드 에러 감지 ({next_log})",
                    "assign_to": "code-quality",
                    "detail": content[:300]
                })
        except:
            pass
except:
    pass

# ── 결과 출력 ───────────────────────────────────────
print(f"""
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 Proactive Scan 결과
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━""".strip())

for key, val in scan_results.items():
    label = {
        "uncommitted_changes": "미커밋 변경",
        "type_errors": "타입 에러",
        "lint_errors": "린트 에러",
        "todo_count": "TODO/FIXME",
        "security_vulns": "보안 취약점",
        "rubocop_offenses": "Rubocop 위반",
        "console_error_warn": "console.error/warn",
        "empty_catch": "빈 catch 블록",
        "throw_count": "throw/reject",
        "error_boundary": "ErrorBoundary",
        "next_build_errors": "Next.js 빌드 에러"
    }.get(key, key)
    icon = "✅" if val == 0 else "⚠️"
    print(f"  {icon} {label}: {val}")

if not findings:
    print(f"\n✅ 프로젝트 정상 — 새 기능 또는 개선 작업을 기획하세요.")
    print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    sys.exit(0)

# ── 이슈 자동 생성 ──────────────────────────────────
next_id = registry["stats"].get("total_issues", 0) + 1
created = 0

for f in findings:
    # 중복 체크: 같은 타입+제목의 READY/IN_PROGRESS 이슈가 있으면 스킵
    dup = False
    for existing in registry["issues"]:
        if (existing.get("type") == f["type"] and
            existing.get("status") in ("READY", "IN_PROGRESS") and
            f["title"][:20] in existing.get("title", "")):
            dup = True
            break
    if dup:
        continue

    issue = {
        "id": f"ISS-{next_id:03d}",
        "type": f["type"],
        "title": f["title"],
        "priority": f["priority"],
        "status": "READY",
        "assign_to": f["assign_to"],
        "created_at": datetime.datetime.now().isoformat(),
        "created_by": "proactive-scan",
        "depth": 0,
        "detail": f.get("detail", ""),
        "parent": None
    }
    registry["issues"].append(issue)
    next_id += 1
    created += 1
    print(f"\n  📌 이슈 생성: {issue['id']} [{issue['priority']}] {issue['title']}")
    print(f"     → {issue['assign_to']}")

registry["stats"]["total_issues"] = next_id - 1

with open(REGISTRY, 'w') as f:
    json.dump(registry, f, indent=2, ensure_ascii=False)

print(f"\n📊 새 이슈 {created}개 생성됨")
if created > 0:
    print(f"\n[자동 실행 지시]")
    print(f"질문하지 마라. READY 이슈를 우선순위 순으로 즉시 처리하라.")
print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

PYEOF
