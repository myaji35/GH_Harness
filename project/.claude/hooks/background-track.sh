#!/bin/bash
# background-track.sh — background 서브에이전트 동시 실행 카운터 관리 (ISS-349)
#
# 용도: dispatch가 background 승인 → 스폰 측이 claim, 완료 시 on_complete가 release.
#       registry.json의 background_state.{active,issues}를 갱신하여 동시≤2를 강제한다.
#
# 사용법:
#   bash background-track.sh claim   <ISSUE_ID>   # background 스폰 시 (status→BACKGROUND_RUNNING)
#   bash background-track.sh release <ISSUE_ID>   # 완료 시 (active에서 제거)
#   bash background-track.sh status               # 현재 active 카운트 출력
#
# 동시 한도(BG_MAX=2) 초과 시 claim은 exit 1 (거부) — 스폰 측은 동기 실행으로 폴백.

ACTION="${1:-status}"
ISSUE_ID="${2:-}"
REGISTRY="${REGISTRY:-.claude/issue-db/registry.json}"
BG_MAX="${BG_MAX:-2}"

[ -f "$REGISTRY" ] || { echo "registry 없음"; exit 0; }

python3 - "$ACTION" "$ISSUE_ID" "$REGISTRY" "$BG_MAX" <<'PY'
import json, sys
action, issue_id, reg_path, bg_max = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
d = json.load(open(reg_path))
st = d.setdefault("background_state", {"active": 0, "issues": []})

# stale 정리: 살아있는 background 이슈만 유지
alive = []
for bid in st.get("issues", []):
    bi = next((x for x in d.get("issues", []) if x.get("id") == bid), None)
    if bi and bi.get("status") in ("IN_PROGRESS", "BACKGROUND_RUNNING"):
        alive.append(bid)
st["issues"] = alive

if action == "claim":
    if issue_id in st["issues"]:
        pass  # 이미 claim됨 (idempotent)
    elif len(st["issues"]) >= bg_max:
        st["active"] = len(st["issues"])
        json.dump(d, open(reg_path, "w"), ensure_ascii=False, indent=2)
        print(f"REJECT (동시 {len(st['issues'])}/{bg_max} 한도 도달)")
        sys.exit(1)
    else:
        st["issues"].append(issue_id)
        for x in d.get("issues", []):
            if x.get("id") == issue_id:
                x["status"] = "BACKGROUND_RUNNING"
    st["active"] = len(st["issues"])
    json.dump(d, open(reg_path, "w"), ensure_ascii=False, indent=2)
    print(f"CLAIM ok ({st['active']}/{bg_max})")

elif action == "release":
    st["issues"] = [b for b in st["issues"] if b != issue_id]
    st["active"] = len(st["issues"])
    # BACKGROUND_RUNNING → IN_PROGRESS 환원 (on_complete가 최종 status 결정)
    for x in d.get("issues", []):
        if x.get("id") == issue_id and x.get("status") == "BACKGROUND_RUNNING":
            x["status"] = "IN_PROGRESS"
    json.dump(d, open(reg_path, "w"), ensure_ascii=False, indent=2)
    print(f"RELEASE ok ({st['active']}/{bg_max})")

else:  # status
    st["active"] = len(st["issues"])
    json.dump(d, open(reg_path, "w"), ensure_ascii=False, indent=2)
    print(f"active={st['active']}/{bg_max} issues={st['issues']}")
PY
