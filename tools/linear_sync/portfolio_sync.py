#!/usr/bin/env python3
"""HAR 팀의 여러 로컬 레지스트리를 Linear 프로젝트에 동기화한다."""

import argparse
from collections import deque
import hashlib
import json
from pathlib import Path

try:
    from . import linear_sync as sync
except ImportError:
    import linear_sync as sync


HERE = Path(__file__).resolve().parent
COUNT_KEYS = ("create", "update", "unchanged", "pull", "conflict", "failed")
EXCEPTIONS = (sync.LinearError, KeyError, TypeError, ValueError, OSError)


def load_portfolio():
    return json.loads((HERE / "portfolio.json").read_text(encoding="utf-8"))


def project_description(project):
    return f"{project['summary']}\n\n로컬 경로: {project['dir']}\n레지스트리: .claude/issue-db/registry.json"


def wanted_state_name(state, names):
    kind = state["type"].lower()
    if kind == "duplicate":
        return None
    name = state["name"].lower()
    if kind == "started" and name in ("in review", names.get("In Review", "").lower()):
        return names["In Review"]
    if kind == "canceled" and name in ("duplicate", names.get("duplicate", "").lower()):
        return names["duplicate"]
    return names.get(kind)


def local_projects(config, only=None):
    result = []
    for project in config["projects"]:
        if only and project["dir"] != only:
            continue
        row = {"dir": project["dir"], "name": project["name"], "project_action": None,
               "counts": {key: 0 for key in COUNT_KEYS}, "omitted": 0, "warnings": []}
        folder = Path(config["base_dir"]) / project["dir"]
        path = folder / ".claude/issue-db/registry.json"
        entry = {"spec": project, "row": row, "path": path, "linked": [], "candidates": deque(), "selected": []}
        if not folder.is_dir():
            row["warnings"].append("프로젝트 디렉터리 없음")
            entry["skip"] = True
        elif not path.is_file():
            row["warnings"].append("레지스트리 없음: 프로젝트만 처리")
        else:
            try:
                registry = sync.read_registry(path)
                if not isinstance(registry.get("issues"), list):
                    raise ValueError("issues must be a list")
                for issue in registry["issues"]:
                    if not isinstance(issue, dict):
                        raise ValueError("issue must be an object")
                    if ((issue.get("payload") or {}).get("linear") or {}).get("id"):
                        entry["linked"].append(issue)
                    elif issue.get("status") in sync.OPEN:
                        entry["candidates"].append(issue)
                entry["candidates"] = deque(sorted(entry["candidates"], key=candidate_key))
            except (OSError, ValueError, TypeError, AttributeError) as exc:
                row["warnings"].append("레지스트리 읽기 실패: " + type(exc).__name__)
                entry["skip"] = True
        result.append(entry)
    return result


def candidate_key(issue):
    status_rank = 0 if issue.get("status") in ("IN_PROGRESS", "AWAITING_USER") else 1
    updated = sync.latest(issue.get("updated_at"), issue.get("created_at"))
    recent = updated.timestamp() if updated else float("-inf")
    return (status_rank, sync.priority(issue, {}) or 5, -recent, str(issue.get("id", "")))


def allocate(entries, available, quota):
    """Give each project at most one new issue per round."""
    available = max(0, available)
    for entry in entries:
        linked_open = sum(issue.get("status") in sync.OPEN for issue in entry["linked"])
        entry["slots"] = max(0, quota - linked_open)
    while available and any(entry["candidates"] and entry["slots"] for entry in entries):
        for entry in entries:
            if not available:
                break
            if entry["candidates"] and entry["slots"]:
                entry["selected"].append(entry["candidates"].popleft())
                entry["slots"] -= 1
                available -= 1
    for entry in entries:
        entry["row"]["omitted"] = len(entry["candidates"])


def active_count(client):
    issues = sync.all_nodes(client, "issues", "id state{type}")
    return sum((issue.get("state") or {}).get("type", "").lower() not in ("completed", "canceled") for issue in issues)


def metadata(client, config):
    teams = sync.all_nodes(client, "teams", "id key name")
    team = next((item for item in teams if item["key"] == config["team_key"]), None)
    if not team:
        raise sync.LinearError("HAR 팀을 찾지 못함")
    states = [item for item in sync.all_nodes(client, "workflowStates", "id name type team{id}")
              if (item.get("team") or {}).get("id") == team["id"]]
    projects = [item for item in sync.all_nodes(client, "projects", "id name description teams{nodes{id}}")
                if team["id"] in [node["id"] for node in item["teams"]["nodes"]]]
    labels = [item for item in sync.all_nodes(client, "issueLabels", "id name team{id}")
              if not item.get("team") or item["team"]["id"] == team["id"]]
    return {"team": team, "states": states, "projects": projects, "labels": labels}


def localize_team(client, ctx, config, apply, warnings):
    team = ctx["team"]
    if team["name"] != config["team_name_ko"]:
        if apply:
            data = client.call("mutation($id:String!,$input:TeamUpdateInput!){teamUpdate(id:$id,input:$input){success}}",
                               {"id": team["id"], "input": {"name": config["team_name_ko"]}})["teamUpdate"]
            if not data["success"]:
                raise sync.LinearError("팀 이름 갱신 실패")
            team["name"] = config["team_name_ko"]
        else:
            warnings.append("팀 이름 한글화 예정")
    for state in ctx["states"]:
        target = wanted_state_name(state, config["state_names_ko"])
        if (not target or state["name"].casefold() == target.casefold()
                or any(other["id"] != state["id"] and other["name"].casefold() == target.casefold()
                       for other in ctx["states"])):
            continue
        if apply:
            try:
                data = client.call("mutation($id:String!,$input:WorkflowStateUpdateInput!){workflowStateUpdate(id:$id,input:$input){success}}",
                                   {"id": state["id"], "input": {"name": target}})["workflowStateUpdate"]
                if not data["success"]:
                    raise sync.LinearError("상태 이름 갱신 실패")
                state["name"] = target
            except EXCEPTIONS as exc:
                warnings.append("상태 한글화 실패: " + type(exc).__name__)
        else:
            warnings.append("상태 한글화 예정: " + state["name"] + " → " + target)


def rename_workspace_labels(client, ctx, config, apply, warnings):
    for label in ctx["labels"]:
        target = config.get("workspace_label_renames", {}).get(label["name"])
        if not target or label["name"] == target:
            continue
        if not apply:
            warnings.append("라벨 이름 변경 예정: " + label["name"] + " → " + target)
            continue
        data = client.call("mutation($id:String!,$input:IssueLabelUpdateInput!){issueLabelUpdate(id:$id,input:$input){success}}",
                           {"id": label["id"], "input": {"name": target}})["issueLabelUpdate"]
        if not data["success"]:
            raise sync.LinearError("라벨 이름 변경 실패")
        label["name"] = target


def ensure_project(client, ctx, spec, apply):
    projects = ctx["projects"]
    project = next((p for p in projects if p["name"] == spec["name"]), None)
    if not project and spec.get("linear_project_alias"):
        project = next((p for p in projects if p["name"] == spec["linear_project_alias"]), None)
    description = project_description(spec)
    if not project:
        if not apply:
            return None, "create"
        data = client.call("mutation($input:ProjectCreateInput!){projectCreate(input:$input){success project{id name description}}}",
                           {"input": {"name": spec["name"], "description": description, "teamIds": [ctx["team"]["id"]]}})["projectCreate"]
        if not data["success"] or not data["project"]:
            raise sync.LinearError("프로젝트 생성 실패")
        project = data["project"]
        projects.append(project)
        return project, "create"
    if project["name"] != spec["name"] or project.get("description") != description:
        if apply:
            data = client.call("mutation($id:String!,$input:ProjectUpdateInput!){projectUpdate(id:$id,input:$input){success}}",
                               {"id": project["id"], "input": {"name": spec["name"], "description": description}})["projectUpdate"]
            if not data["success"]:
                raise sync.LinearError("프로젝트 갱신 실패")
            project.update(name=spec["name"], description=description)
        return project, "update"
    return project, "unchanged"


def issue_description(issue, spec):
    payload = issue.get("payload") or {}
    source = payload.get("ref") or payload.get("origin") or ""
    fields = (("유형", spec.get("label_names_ko", {}).get(issue.get("type"), issue.get("type"))), ("우선순위", issue.get("priority")),
              ("출처", source), ("생성", issue.get("created_at")),
              ("프로젝트", f"{spec['name']} ({spec['dir']})"))
    return "\n".join(f"{name}: {value}" for name, value in fields if isinstance(value, (str, int, float, bool)))


def remember_description(path, issue, spec, digest):
    def change(current):
        if hashlib.sha256(issue_description(current, spec).encode("utf-8")).hexdigest() == digest:
            current.setdefault("payload", {}).setdefault("linear", {})["synced_description_hash"] = digest
        return True
    sync.registry_transaction(path, issue["id"], change)


def sync_one(client, entry, ctx, base_config, config, apply, now):
    issue_ctx = {"team": ctx["team"], "states": ctx["states"], "project": entry.get("project"),
                 "labels": ctx["labels"], "use_labels": True, "label_names_ko": config["label_names_ko"]}
    row = entry["row"]
    for issue in entry["linked"] + entry["selected"]:
        linked = ((issue.get("payload") or {}).get("linear") or {})
        try:
            remote = sync.fetch_issue(client, linked["id"]) if linked.get("id") else None
            if linked.get("id") and not remote:
                raise sync.LinearError("연결된 Linear 이슈 없음")
            action, state, level = sync.plan_issue(issue, remote, issue_ctx, base_config)
            spec = {**entry["spec"], "label_names_ko": config["label_names_ko"]}
            description = issue_description(issue, spec)
            digest = hashlib.sha256(description.encode("utf-8")).hexdigest()
            if action == "unchanged" and linked.get("synced_description_hash") != digest:
                action = "update"
            if not apply:
                row["counts"][action] += 1
                continue
            if action == "unchanged":
                if any(key not in linked for key in sync.SYNC_FIELDS):
                    sync.record_snapshot(entry["path"], issue, sync.desired_snapshot(issue, state, level, issue_ctx))
            elif action == "pull":
                if not sync.record_pull(entry["path"], issue, remote, now):
                    action = "conflict"
            if action in ("create", "update", "conflict"):
                item = sync.issue_input(issue, base_config, issue_ctx, client, True,
                                        description_text=description)
                pushed = sync.mutate_issue(client, issue, item, issue_ctx)
                sync.record_push(entry["path"], issue, pushed,
                                 sync.desired_snapshot(issue, state, level, issue_ctx), now)
                remember_description(entry["path"], issue, spec, digest)
            row["counts"][action] += 1
        except EXCEPTIONS as exc:
            row["counts"]["failed"] += 1
            row["warnings"].append(f"{issue.get('id', '?')}: {type(exc).__name__}")


def run(config, client=None, apply=False, only=None, now=None):
    now = now or sync.utcnow()
    entries = local_projects(config, only)
    summary = {"mode": "apply" if apply else "dry-run", "key_needed": client is None,
               "team_key": config["team_key"], "active_issues": None,
               "active_issue_cap": config["active_issue_cap"], "omitted_by_budget": 0,
               "projects": [entry["row"] for entry in entries], "warnings": []}
    if not client:
        allocate(entries, 0, int(config["per_project_quota"]))
        for entry in entries:
            entry["row"]["counts"]["update"] = len(entry["linked"])
        summary["omitted_by_budget"] = sum(entry["row"]["omitted"] for entry in entries)
        summary["warnings"].append("Linear API 키 없음: 로컬 분석만 수행")
        return summary
    try:
        ctx = metadata(client, config)
    except EXCEPTIONS as exc:
        summary["warnings"].append("Linear 메타데이터 조회 실패: " + type(exc).__name__)
        return summary
    try:
        summary["active_issues"] = active_count(client)
    except EXCEPTIONS as exc:
        summary["warnings"].append("활성 이슈 실측 실패: 신규 생성 보류 (" + type(exc).__name__ + ")")
    try:
        localize_team(client, ctx, config, apply, summary["warnings"])
    except EXCEPTIONS as exc:
        summary["warnings"].append("팀 이름 갱신 실패: " + type(exc).__name__)
    try:
        rename_workspace_labels(client, ctx, config, apply, summary["warnings"])
    except EXCEPTIONS as exc:
        summary["warnings"].append("라벨 이름 변경 실패: " + type(exc).__name__)
    available = max(0, int(config["active_issue_cap"]) - summary["active_issues"]) if summary["active_issues"] is not None else 0
    eligible = [entry for entry in entries if not entry.get("skip")]
    allocate(eligible, available, int(config["per_project_quota"]))
    summary["omitted_by_budget"] = sum(entry["row"]["omitted"] for entry in eligible)
    base_config = sync.load_config()
    base_config["done_window_days"] = config["done_window_days"]
    for entry in eligible:
        try:
            entry["project"], entry["row"]["project_action"] = ensure_project(client, ctx, entry["spec"], apply)
            if apply and not entry["project"]:
                raise sync.LinearError("프로젝트 ID 없음")
            sync_one(client, entry, ctx, base_config, config, apply, now)
        except EXCEPTIONS as exc:
            entry["row"]["counts"]["failed"] += len(entry["linked"]) + len(entry["selected"])
            entry["row"]["warnings"].append("프로젝트 처리 실패: " + type(exc).__name__)
    return summary


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--only", metavar="DIR")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    config = load_portfolio()
    if args.only and args.only not in {p["dir"] for p in config["projects"]}:
        parser.error("portfolio.json에 없는 프로젝트 디렉터리")
    key = sync.load_key()
    summary = run(config, sync.GraphQLClient(key) if key else None, args.apply, args.only)
    (HERE / "last_portfolio_run.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if args.json:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    else:
        measured = summary["active_issues"] if summary["active_issues"] is not None else "미측정"
        print(f"활성 이슈: {measured}/{summary['active_issue_cap']} | 예산 제외 후보: {summary['omitted_by_budget']}")
        labels = (("create", "생성"), ("update", "갱신"), ("unchanged", "유지"),
                  ("pull", "당겨옴"), ("conflict", "충돌"), ("failed", "실패"))
        for row in summary["projects"]:
            counts = " ".join(f"{label} {row['counts'][key]}" for key, label in labels)
            print(f"{row['name']} ({row['dir']}): {counts}")
            for warning in row["warnings"]:
                print("  경고: " + warning)
        for warning in summary["warnings"]:
            print("경고: " + warning)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
