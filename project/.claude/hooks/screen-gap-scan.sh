#!/bin/bash
# screen-gap-scan.sh — Screen Gap Scanner (화면 갭 스캐너)
#
# 프로젝트의 라우트/메뉴 구조를 스캔하여 "화면은 있는데 빠진 상식적 비즈니스 기능"을
# 자동 탐지하고 SCREEN_GAP 이슈를 생성한다.
#
# proactive-scan.sh가 "코드 결함"을 찾는다면,
# screen-gap-scan.sh는 "비즈니스 결함(빠진 기능)"을 찾는다.
#
# 트리거:
#   - "화면 갭 스캔" / "screen gap" / "빠진 기능 찾아줘" / "비즈니스 니즈 점검"
#   - harness 시작 시 자동 (proactive-scan.sh 이후)
#   - 새 라우트/페이지 추가 후
#
# 스캔 대상:
#   - Rails: config/routes.rb
#   - Next.js: app/ 또는 pages/ 디렉터리
#   - React Router: src/routes 또는 src/App.tsx
#   - Remix: app/routes/
#   - Python Flask/FastAPI: 라우트 데코레이터
#
# 출력: SCREEN_GAP 이슈 (P1~P3) → plan-harness:product 모드로 스토리 분해

set -e

REGISTRY=".claude/issue-db/registry.json"

if [ ! -f "$REGISTRY" ]; then
  echo "[ScreenGap] registry.json 없음 — 스캔 스킵"
  exit 0
fi

python3 << 'PYEOF'
import json, os, re, subprocess, sys, datetime, glob

REGISTRY = ".claude/issue-db/registry.json"

try:
    with open(REGISTRY, 'r') as f:
        registry = json.load(f)
except:
    print("[ScreenGap] registry.json 읽기 실패")
    sys.exit(0)

# 백로그 과다 시 스킵
pending_ready = sum(1 for i in registry.get("issues", []) if i.get("status") == "READY")
if pending_ready > 15:
    print(f"[ScreenGap] 백로그 {pending_ready}개 과다 — 스캔 스킵")
    sys.exit(0)

# 일일 스캔 한도
today = datetime.date.today().isoformat()
scan_state = registry.setdefault("screen_gap_state", {"date": today, "count": 0, "last_routes": []})
if scan_state.get("date") != today:
    scan_state.update({"date": today, "count": 0})
if scan_state["count"] >= 3:
    print(f"[ScreenGap] 일일 스캔 한도 초과 ({scan_state['count']}/3) — 스킵")
    sys.exit(0)
scan_state["count"] += 1

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 화면 패턴별 상식적 기대 기능 매트릭스
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SCREEN_EXPECTATIONS = {
    "index": {
        "label": "목록 화면",
        "expects": [
            {"feature": "검색/필터", "keywords": ["search", "filter", "query", "q=", "검색", "필터"], "priority": "P2"},
            {"feature": "정렬", "keywords": ["sort", "order", "정렬", "orderBy", "sort_by"], "priority": "P2"},
            {"feature": "페이지네이션", "keywords": ["page", "pagina", "offset", "limit", "cursor", "페이지", "더보기", "infinite"], "priority": "P2"},
            {"feature": "빈 상태 메시지", "keywords": ["empty", "no-data", "없습니다", "데이터가 없", "no_results", "EmptyState"], "priority": "P3"},
            {"feature": "신규 생성 버튼/링크", "keywords": ["new", "create", "add", "추가", "생성", "등록", "New"], "priority": "P1"},
        ]
    },
    "show": {
        "label": "상세 화면",
        "expects": [
            {"feature": "수정 액션", "keywords": ["edit", "update", "수정", "편집", "Edit"], "priority": "P1"},
            {"feature": "삭제 액션", "keywords": ["delete", "destroy", "remove", "삭제", "Delete", "confirm"], "priority": "P1"},
            {"feature": "뒤로가기/목록 링크", "keywords": ["back", "list", "index", "목록", "돌아가기", "Back"], "priority": "P3"},
            {"feature": "관련 항목 링크", "keywords": ["related", "associated", "see_also", "관련", "연결"], "priority": "P3"},
        ]
    },
    "form": {
        "label": "폼 화면 (생성/수정)",
        "expects": [
            {"feature": "필수값 검증", "keywords": ["required", "validate", "validation", "필수", "errors", "invalid"], "priority": "P1"},
            {"feature": "저장 피드백", "keywords": ["success", "toast", "flash", "notice", "alert", "저장 완료", "성공"], "priority": "P2"},
            {"feature": "취소/뒤로가기", "keywords": ["cancel", "back", "취소", "돌아가기", "Cancel"], "priority": "P2"},
            {"feature": "로딩 상태", "keywords": ["loading", "submitting", "saving", "spinner", "disabled", "로딩"], "priority": "P3"},
        ]
    },
    "dashboard": {
        "label": "대시보드",
        "expects": [
            {"feature": "KPI/요약 카드", "keywords": ["stat", "kpi", "summary", "count", "total", "요약", "통계", "Card"], "priority": "P1"},
            {"feature": "최근 활동", "keywords": ["recent", "activity", "latest", "최근", "활동", "timeline"], "priority": "P2"},
            {"feature": "빠른 액션", "keywords": ["quick", "action", "shortcut", "빠른", "바로가기"], "priority": "P2"},
        ]
    },
    "settings": {
        "label": "설정",
        "expects": [
            {"feature": "프로필 수정", "keywords": ["profile", "name", "email", "프로필", "이름"], "priority": "P2"},
            {"feature": "비밀번호 변경", "keywords": ["password", "비밀번호", "change_password"], "priority": "P2"},
        ]
    }
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1단계: 프로젝트 프레임워크 감지 + 라우트 추출
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

routes = []  # [{path, name, type(index/show/form/dashboard/settings), files[]}]

STATIC_PAGE_KEYWORDS = [
    "policy", "guide", "announcement", "notice", "readme",
    "privacy", "terms", "license", "about", "help", "faq",
    "disclosure", "compliance", "audit_log", "dispute",
    "sandbox_report", "evidence", "report",  # 증빙/리포트 정적 뷰
]

AUTH_FORM_KEYWORDS = [
    "login", "signin", "sign_in", "signup", "sign_up", "register",
    "logout", "signout", "password", "forgot", "reset",
    "oauth", "callback", "verify", "profile/setup", "profile/edit",
]

def is_api_action(route):
    """action 문자열 또는 HTTP 메서드 기반 API 여부 판단"""
    action = (route.get("action", "") or "").lower()
    # POST-only, DELETE, PUT/PATCH는 거의 API/RPC
    verb = (route.get("verb", "") or "").upper()
    if verb in ("POST", "DELETE", "PUT", "PATCH"):
        return True
    # Rails 컨벤션 — "controller#action"의 action이 refresh/sync/search/complete/start 등
    if "#" in action:
        _, act = action.rsplit("#", 1)
        if act in ("refresh", "sync", "search", "complete", "start", "send_message",
                   "stream_message", "demo_search", "term_search", "gap_summary",
                   "legal_search", "compare_refresh", "crawl_diagnostics"):
            return True
    return False

def classify_screen(path, name="", route=None):
    """라우트 경로에서 화면 패턴 추론"""
    p = (path + name).lower()
    # API/JSON 엔드포인트 우선 감지
    if route and is_api_action(route):
        return "api"
    # 인증/프로필 폼 경로는 목록 아님
    if any(k in p for k in AUTH_FORM_KEYWORDS):
        return "auth_form"
    # 정적 안내 페이지 (policy/guide/report 등)
    if any(k in p for k in STATIC_PAGE_KEYWORDS):
        return "static"
    if "dashboard" in p or "home" in p or p.rstrip("/") == "":
        return "dashboard"
    if "setting" in p or "config" in p or "preference" in p:
        return "settings"
    if "new" in p or "create" in p or "edit" in p:
        return "form"
    if re.search(r'[:$]\w+|/\d+|/\[', p):  # :id, [id], /123 등 동적 세그먼트
        return "show"
    return "index"

def find_associated_files(route_path):
    """라우트에 연결된 뷰/컴포넌트 파일 탐색"""
    files = []
    # 라우트 이름에서 리소스명 추출
    parts = [p for p in route_path.strip("/").split("/") if p and not p.startswith(":") and not p.startswith("[")]
    if not parts:
        return files
    resource = parts[-1] if parts else ""

    # 가능한 파일 경로 패턴
    search_patterns = [
        f"**/*{resource}*",
        f"app/views/**/*{resource}*",
        f"src/**/*{resource}*",
        f"pages/**/*{resource}*",
        f"app/**/*{resource}*",
    ]
    for pattern in search_patterns:
        for f in glob.glob(pattern, recursive=True):
            if not any(skip in f for skip in ["node_modules", ".git", ".next", "__pycache__", "vendor"]):
                files.append(f)
    return files[:20]  # 너무 많으면 20개 제한


# ── Rails ──
if os.path.exists("config/routes.rb"):
    print("[ScreenGap] Rails 프로젝트 감지")
    try:
        result = subprocess.run(["bin/rails", "routes", "--expanded"], capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            result = subprocess.run(["bundle", "exec", "rails", "routes"], capture_output=True, text=True, timeout=30)

        if result.stdout:
            current_route = {}
            for line in result.stdout.split("\n"):
                line = line.strip()
                if line.startswith("--[ Route"):
                    if current_route.get("path"):
                        routes.append(current_route)
                    current_route = {}
                elif "Prefix" in line and "|" in line:
                    current_route["name"] = line.split("|")[1].strip()
                elif "Verb" in line and "|" in line:
                    current_route["verb"] = line.split("|")[1].strip()
                elif "URI" in line and "|" in line:
                    uri = line.split("|")[1].strip()
                    current_route["path"] = re.sub(r'\(.:format\)', '', uri).strip()
                elif "Controller#Action" in line and "|" in line:
                    current_route["action"] = line.split("|")[1].strip()

            if current_route.get("path"):
                routes.append(current_route)

            # rails routes --expanded가 안 먹히면 간단 파싱
            if not routes:
                for line in result.stdout.split("\n"):
                    match = re.match(r'\s*(\w+)?\s+(GET|POST|PUT|PATCH|DELETE)\s+(\S+)\s+(\S+)', line)
                    if match:
                        routes.append({
                            "name": match.group(1) or "",
                            "verb": match.group(2),
                            "path": re.sub(r'\(.:format\)', '', match.group(3)).strip(),
                            "action": match.group(4) or ""
                        })
    except:
        # routes.rb 직접 파싱 (fallback)
        with open("config/routes.rb", 'r') as f:
            content = f.read()
        for m in re.finditer(r'resources?\s+:(\w+)', content):
            resource = m.group(1)
            routes.extend([
                {"path": f"/{resource}", "name": f"{resource}_index", "action": f"{resource}#index"},
                {"path": f"/{resource}/new", "name": f"new_{resource}", "action": f"{resource}#new"},
                {"path": f"/{resource}/:id", "name": f"{resource}_show", "action": f"{resource}#show"},
                {"path": f"/{resource}/:id/edit", "name": f"edit_{resource}", "action": f"{resource}#edit"},
            ])

# ── Next.js (App Router) ──
elif os.path.exists("app") and (os.path.exists("next.config.js") or os.path.exists("next.config.ts") or os.path.exists("next.config.mjs")):
    print("[ScreenGap] Next.js App Router 감지")
    for root, dirs, files in os.walk("app"):
        dirs[:] = [d for d in dirs if d not in ["node_modules", ".next", "api", "_components"]]
        for f in files:
            if f in ("page.tsx", "page.ts", "page.jsx", "page.js"):
                rel = os.path.relpath(root, "app")
                route_path = "/" + rel.replace("\\", "/") if rel != "." else "/"
                # Next.js 동적 세그먼트: [id] → :id
                route_path = re.sub(r'\[(\w+)\]', r':\1', route_path)
                routes.append({
                    "path": route_path,
                    "name": rel.replace("/", "_"),
                    "action": os.path.join(root, f)
                })

# ── Pages Router ──
elif os.path.exists("pages") and (os.path.exists("next.config.js") or os.path.exists("next.config.ts") or os.path.exists("next.config.mjs")):
    print("[ScreenGap] Next.js Pages Router 감지")
    for root, dirs, files in os.walk("pages"):
        dirs[:] = [d for d in dirs if d not in ["node_modules", ".next", "api"]]
        for f in files:
            if f.endswith((".tsx", ".ts", ".jsx", ".js")) and not f.startswith("_"):
                rel = os.path.relpath(os.path.join(root, f), "pages")
                route_path = "/" + re.sub(r'\.(tsx?|jsx?)$', '', rel).replace("\\", "/")
                route_path = route_path.replace("/index", "")
                route_path = re.sub(r'\[(\w+)\]', r':\1', route_path)
                if not route_path:
                    route_path = "/"
                routes.append({
                    "path": route_path,
                    "name": os.path.splitext(f)[0],
                    "action": os.path.join(root, f)
                })

# ── React Router (src/App.tsx 또는 src/routes/) ──
elif os.path.exists("src"):
    route_files = glob.glob("src/**/route*", recursive=True) + glob.glob("src/**/App.tsx", recursive=True) + glob.glob("src/**/App.jsx", recursive=True)
    for rf in route_files:
        try:
            with open(rf, 'r') as f:
                content = f.read()
            for m in re.finditer(r'path[=:]\s*["\']([^"\']+)["\']', content):
                routes.append({
                    "path": m.group(1),
                    "name": m.group(1).strip("/").replace("/", "_") or "root",
                    "action": rf
                })
        except:
            pass

# ── Python (Flask/FastAPI) ──
elif os.path.exists("requirements.txt") or os.path.exists("pyproject.toml"):
    print("[ScreenGap] Python 프로젝트 감지")
    py_files = glob.glob("**/*.py", recursive=True)
    for pf in py_files:
        if any(skip in pf for skip in ["venv", ".git", "__pycache__", "migration"]):
            continue
        try:
            with open(pf, 'r') as f:
                content = f.read()
            # Flask: @app.route("/path")  FastAPI: @app.get("/path")
            for m in re.finditer(r'@\w+\.(route|get|post|put|delete|patch)\s*\(\s*["\']([^"\']+)["\']', content):
                routes.append({
                    "path": m.group(2),
                    "name": m.group(2).strip("/").replace("/", "_") or "root",
                    "action": pf
                })
        except:
            pass

# ── 라우트 중복 제거 + 분류 ──
seen_paths = set()
classified_routes = []
for r in routes:
    path = r.get("path", "")
    if path in seen_paths or not path:
        continue
    # API/asset 라우트 제외
    if any(skip in path.lower() for skip in ["/api/", "/assets/", "/public/", "/static/", ".json", ".xml", "/health", "/favicon"]):
        continue
    seen_paths.add(path)
    screen_type = classify_screen(path, r.get("name", ""), route=r)
    # api/static/auth_form은 갭 탐지 대상 아님 — 분류만 기록하고 제외
    if screen_type in ("api", "static", "auth_form"):
        continue
    r["screen_type"] = screen_type
    r["files"] = find_associated_files(path)
    classified_routes.append(r)

if not classified_routes:
    print("[ScreenGap] 라우트를 찾을 수 없음 — 스캔 종료")
    scan_state["count"] -= 1  # 실패는 횟수 차감
    with open(REGISTRY, 'w') as f:
        json.dump(registry, f, indent=2, ensure_ascii=False)
    sys.exit(0)

print(f"[ScreenGap] {len(classified_routes)}개 화면 감지")

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2단계: 각 화면의 관련 파일에서 기대 기능 키워드 탐색
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

gaps = []  # [{route, screen_type, missing_feature, priority}]

for route in classified_routes:
    screen_type = route["screen_type"]
    expectations = SCREEN_EXPECTATIONS.get(screen_type, {}).get("expects", [])
    if not expectations:
        continue

    # 관련 파일 내용 합치기
    combined_content = ""
    search_files = route.get("files", [])
    # action 파일도 포함
    if route.get("action") and os.path.isfile(route["action"]):
        search_files.append(route["action"])

    for fpath in search_files:
        try:
            with open(fpath, 'r', errors='ignore') as f:
                combined_content += f.read() + "\n"
        except:
            pass

    # 파일이 아예 없으면 라우트 경로 근처 탐색
    if not combined_content.strip():
        parts = [p for p in route["path"].strip("/").split("/") if p and not p.startswith(":") and not p.startswith("[")]
        if parts:
            resource = parts[0]
            try:
                grep_result = subprocess.run(
                    ["grep", "-rl", resource, ".", "--include=*.tsx", "--include=*.ts",
                     "--include=*.jsx", "--include=*.js", "--include=*.erb", "--include=*.html",
                     "--include=*.py", "--include=*.rb",
                     "--exclude-dir=node_modules", "--exclude-dir=.git", "--exclude-dir=.next",
                     "--exclude-dir=vendor"],
                    capture_output=True, text=True, timeout=10
                )
                for gf in grep_result.stdout.strip().split("\n")[:10]:
                    if gf.strip():
                        try:
                            with open(gf.strip(), 'r', errors='ignore') as f:
                                combined_content += f.read() + "\n"
                        except:
                            pass
            except:
                pass

    combined_lower = combined_content.lower()

    for expect in expectations:
        found = any(kw.lower() in combined_lower for kw in expect["keywords"])
        if not found:
            gaps.append({
                "route": route["path"],
                "screen_type": screen_type,
                "screen_label": SCREEN_EXPECTATIONS[screen_type]["label"],
                "missing_feature": expect["feature"],
                "priority": expect["priority"],
            })

if not gaps:
    print("[ScreenGap] 모든 화면에 상식적 기능 구비 — 갭 없음")
    scan_state["last_routes"] = [r["path"] for r in classified_routes]
    with open(REGISTRY, 'w') as f:
        json.dump(registry, f, indent=2, ensure_ascii=False)
    sys.exit(0)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3단계: SCREEN_GAP 이슈 생성 (화면별로 그룹핑)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# 기존 SCREEN_GAP 이슈와 중복 체크
existing_gaps = set()
for iss in registry.get("issues", []):
    if iss.get("type") == "SCREEN_GAP" and iss.get("status") not in ("DONE", "CANCELLED"):
        route = iss.get("payload", {}).get("route", "")
        features = iss.get("payload", {}).get("missing_features", [])
        for feat in features:
            existing_gaps.add(f"{route}:{feat}")

# 화면별로 그룹핑
from collections import defaultdict
grouped = defaultdict(list)
for gap in gaps:
    key = f"{gap['route']}:{gap['missing_feature']}"
    if key not in existing_gaps:
        grouped[gap["route"]].append(gap)

new_issues = []
for route_path, route_gaps in grouped.items():
    if not route_gaps:
        continue

    # 가장 높은 우선순위
    priority_order = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}
    best_priority = min(route_gaps, key=lambda g: priority_order.get(g["priority"], 9))["priority"]

    screen_label = route_gaps[0]["screen_label"]
    missing_names = [g["missing_feature"] for g in route_gaps]

    next_id = f"ISS-{registry['stats']['total_issues'] + 1:03d}"
    issue = {
        "id": next_id,
        "title": f"[Screen Gap] {route_path} ({screen_label}) — {', '.join(missing_names[:3])}{'...' if len(missing_names) > 3 else ''}",
        "type": "SCREEN_GAP",
        "status": "READY",
        "priority": best_priority,
        "assign_to": "plan-harness",
        "depth": 0,
        "retry_count": 0,
        "parent_id": None,
        "depends_on": [],
        "created_at": datetime.datetime.now().isoformat(),
        "payload": {
            "route": route_path,
            "screen_type": route_gaps[0]["screen_type"],
            "screen_label": screen_label,
            "missing_features": missing_names,
            "gap_details": route_gaps,
            "plan_mode": "product",
            "scan_source": "screen-gap-scan"
        },
        "result": None,
        "spawn_rules": []
    }
    registry["issues"].append(issue)
    registry["stats"]["total_issues"] += 1
    new_issues.append(issue)

# 저장
scan_state["last_routes"] = [r["path"] for r in classified_routes]
with open(REGISTRY, 'w') as f:
    json.dump(registry, f, indent=2, ensure_ascii=False)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 출력
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

print(f"\n━━━ Screen Gap Scanner 결과 ━━━")
print(f"  스캔 화면: {len(classified_routes)}개")
print(f"  발견 갭: {len(gaps)}개 (중복 제외 신규 이슈: {len(new_issues)}개)")
print()

# 화면 타입별 요약
from collections import Counter
type_counter = Counter(g["screen_type"] for g in gaps)
for stype, cnt in type_counter.most_common():
    label = SCREEN_EXPECTATIONS.get(stype, {}).get("label", stype)
    print(f"  {label}: {cnt}개 갭")

print()
# 우선순위별 요약
prio_counter = Counter(g["priority"] for g in gaps)
for p in ["P1", "P2", "P3"]:
    if p in prio_counter:
        print(f"  {p}: {prio_counter[p]}건")

if new_issues:
    print(f"\n  → {len(new_issues)}개 SCREEN_GAP 이슈 생성 → plan-harness:product 모드로 스토리 분해 예정")
    for iss in new_issues[:5]:
        print(f"    {iss['id']} [{iss['priority']}] {iss['title']}")
    if len(new_issues) > 5:
        print(f"    ... 외 {len(new_issues) - 5}건")
else:
    print(f"\n  → 신규 이슈 없음 (기존 이슈로 이미 커버)")

PYEOF
