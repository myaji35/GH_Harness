#!/usr/bin/env python3
"""Synchronize the GH_Harness issue registry with Linear."""

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import sys
import time
import urllib.error
import urllib.request


ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
REGISTRY = ROOT / ".claude/issue-db/registry.json"
OPEN = {"BACKLOG", "READY", "IN_PROGRESS", "AWAITING_USER", "HANDED_OFF", "PARTIAL"}
DONE = {"COMPLETED", "DONE"}
PRIORITY_DEFAULT = {"P0": 1, "P1": 2, "P2": 3, "P3": 4}
REVERSE_PRIORITY = {1: "P0", 2: "P1", 3: "P2", 4: "P3"}


def timestamp(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        try:
            seconds = value / 1000 if value >= 1e12 else value
            return dt.datetime.fromtimestamp(seconds, tz=dt.timezone.utc)
        except (OverflowError, OSError, ValueError):
            return None
    if not isinstance(value, str) or not value:
        return None
    try:
        result = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        return result.replace(tzinfo=dt.timezone.utc) if result.tzinfo is None else result.astimezone(dt.timezone.utc)
    except (TypeError, ValueError):
        return None


def utcnow():
    return dt.datetime.now(dt.timezone.utc)


def iso(value):
    return value.isoformat().replace("+00:00", "Z")


def latest(*values):
    return max((parsed for parsed in (timestamp(value) for value in values) if parsed), default=None)


def load_config():
    with (HERE / "config.json").open(encoding="utf-8") as stream:
        return json.load(stream)


def load_key():
    for name in ("XIM_LINEAR_API_KEY", "LINEAR_API_KEY"):
        if os.environ.get(name):
            return os.environ[name].strip()
    env_path = HERE / ".env"
    if env_path.is_file():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            name, value = line.split("=", 1)
            if name.strip() in ("XIM_LINEAR_API_KEY", "LINEAR_API_KEY") and value.strip():
                return value.strip().strip('"\'')
    return None


def read_registry(path=REGISTRY):
    with open(path, encoding="utf-8") as stream:
        return json.load(stream)


def registry_transaction(path, issue_id, change):
    """Re-read under the repository's lock; change only the matching issue."""
    sys.path.insert(0, str(ROOT / ".claude/hooks/lib"))
    from registry_lock import registry_txn
    with registry_txn(str(path)) as registry:
        for issue in registry["issues"]:
            if issue.get("id") == issue_id:
                return change(issue)
    raise ValueError("registry issue disappeared")


def priority(issue, config):
    return int(config.get("priority_map", PRIORITY_DEFAULT).get(issue.get("priority"), 0))


def target_issues(registry, config, now=None, limit=None):
    now = now or utcnow()
    cutoff = now - dt.timedelta(days=int(config["done_window_days"]))
    candidates = []
    linked = []
    for issue in registry["issues"]:
        status = issue.get("status", "")
        linear = (issue.get("payload") or {}).get("linear") or {}
        if linear.get("id"):
            linked.append(issue)
        elif status in OPEN or (status in DONE and (latest(issue.get("completed_at"), issue.get("updated_at")) or dt.datetime.min.replace(tzinfo=dt.timezone.utc)) >= cutoff):
            candidates.append(issue)
    candidates.sort(key=lambda x: (priority(x, config) or 5, -(latest(x.get("updated_at"), x.get("completed_at"), x.get("created_at")) or dt.datetime.min.replace(tzinfo=dt.timezone.utc)).timestamp()))
    cap = int(config["max_open_issues"])
    if limit is not None:
        cap = min(cap, limit)
    selected = candidates[:max(0, cap)]
    # Linked issues always remain eligible, including closed issues.
    return linked + selected, max(0, len(candidates) - len(selected))


def state_category(status, config):
    mapping = config.get("state_map", {})
    if status.startswith("CLOSED") or status in ("OBSOLETED", "ARCHIVED"):
        return mapping.get("CLOSED", "canceled")
    return mapping.get(status, "backlog")


def find_state(status, states, config):
    desired = state_category(status, config)
    if desired == "In Review":
        review = next((s for s in states if s["type"].lower() == "started" and s["name"].lower() in ("in review", "검토 중")), None)
        if review:
            return review
        desired = "started"
    # Match category before names so team-customized workflow names work.
    typed = [s for s in states if s["type"].lower() == desired.lower()]
    names = {"unstarted": ("todo", "to do", "할 일"), "started": ("in progress", "진행 중"), "backlog": ("backlog", "백로그")}
    return next((s for s in typed if s["name"].lower() in names.get(desired, ())), typed[0] if typed else None)


def reverse_state(linear_state, old_status):
    kind = linear_state["type"].lower()
    if kind == "started" and linear_state["name"].lower() in ("in review", "검토 중") and old_status in {"AWAITING_USER", "HANDED_OFF", "PARTIAL"}:
        return old_status
    return {"completed": "COMPLETED", "canceled": "CLOSED", "started": "IN_PROGRESS", "unstarted": "READY", "backlog": "BACKLOG"}.get(kind, old_status)


def description(issue):
    payload = issue.get("payload") or {}
    fields = (("type", issue.get("type")), ("priority", issue.get("priority")), ("ref", payload.get("ref")), ("origin", payload.get("origin")), ("created_at", issue.get("created_at")), ("registry", ".claude/issue-db/registry.json"))
    return "\n".join(f"{name}: {value}" for name, value in fields if isinstance(value, (str, int, float, bool)))


class LinearError(Exception):
    pass


class GraphQLClient:
    def __init__(self, key, opener=None, sleep=time.sleep):
        self.key = key
        self.opener = opener or urllib.request.urlopen
        self.sleep = sleep

    def call(self, query, variables=None):
        body = json.dumps({"query": query, "variables": variables or {}}).encode()
        request = urllib.request.Request("https://api.linear.app/graphql", data=body, headers={"Content-Type": "application/json", "Authorization": self.key}, method="POST")
        for attempt in range(4):
            try:
                with self.opener(request, timeout=30) as response:
                    data = json.load(response)
                errors = data.get("errors") or []
                if errors:
                    codes = {str(e.get("extensions", {}).get("code", "")) for e in errors}
                    if "RATELIMITED" in codes and attempt < 3:
                        self.sleep(2 ** attempt)
                        continue
                    raise LinearError("GraphQL error: " + ",".join(sorted(codes - {""})) if codes - {""} else "GraphQL error")
                return data["data"]
            except urllib.error.HTTPError as exc:
                # Do not emit response bodies: servers may echo request headers.
                if attempt < 3:
                    self.sleep(2 ** attempt)
                    continue
                raise LinearError(f"HTTP {exc.code}") from None
            except (urllib.error.URLError, TimeoutError, OSError, ValueError, KeyError) as exc:
                if attempt < 3:
                    self.sleep(2 ** attempt)
                    continue
                raise LinearError(type(exc).__name__) from None
        raise LinearError("request failed")


def all_nodes(client, field, selection):
    nodes, cursor = [], None
    while True:
        data = client.call(f"query($after:String){{{field}(first:100,after:$after){{nodes{{{selection}}} pageInfo{{hasNextPage endCursor}}}}}}", {"after": cursor})[field]
        nodes.extend(data["nodes"])
        if not data["pageInfo"]["hasNextPage"]:
            return nodes
        cursor = data["pageInfo"]["endCursor"]


def context(client, config):
    teams = all_nodes(client, "teams", "id key name")
    team_key = config.get("team_key")
    if team_key is not None:
        team = next((t for t in teams if t["key"] == team_key), None)
    elif len(teams) == 1:
        team = teams[0]
    elif len(teams) > 1:
        raise LinearError("team_key 를 config.json 에 지정하라")
    else:
        team = None
    if not team:
        raise LinearError("configured team unavailable")
    states = [s for s in all_nodes(client, "workflowStates", "id name type team{id}") if (s.get("team") or {}).get("id") == team["id"]]
    projects = all_nodes(client, "projects", "id name teams{nodes{id}}")
    project = next((p for p in projects if p["name"] == config["project_name"] and team["id"] in [t["id"] for t in p["teams"]["nodes"]]), None)
    labels = [l for l in all_nodes(client, "issueLabels", "id name team{id}") if not l.get("team") or l["team"]["id"] == team["id"]]
    return {"team": team, "states": states, "project": project, "labels": labels}


def fetch_issue(client, linear_id):
    return client.call("query($id:String!){issue(id:$id){id identifier url updatedAt title priority state{id name type} project{id} labels{nodes{id}}}}", {"id": linear_id})["issue"]


def create_project(client, ctx, config):
    data = client.call("mutation($input:ProjectCreateInput!){projectCreate(input:$input){success project{id name}}}", {"input": {"name": config["project_name"], "teamIds": [ctx["team"]["id"]]}})["projectCreate"]
    if not data["success"] or not data["project"]:
        raise LinearError("project creation failed")
    ctx["project"] = data["project"]


def label_id(client, ctx, name):
    label = find_label(ctx["labels"], name)
    if label:
        return label["id"]
    data = client.call("mutation($input:IssueLabelCreateInput!){issueLabelCreate(input:$input){success issueLabel{id name}}}", {"input": {"name": name, "teamId": ctx["team"]["id"]}})["issueLabelCreate"]
    if not data["success"] or not data["issueLabel"]:
        raise LinearError("label creation failed")
    ctx["labels"].append(data["issueLabel"])
    return data["issueLabel"]["id"]


def find_label(labels, name):
    return next((label for label in labels if label["name"].casefold() == name.casefold()), None)


def issue_input(issue, config, ctx, client, apply, description_text=None):
    state = find_state(issue.get("status", ""), ctx["states"], config)
    if not state:
        raise LinearError("workflow state unavailable")
    item = {"title": f"[{issue['id']}] {issue.get('title', '')}", "description": description(issue) if description_text is None else description_text, "stateId": state["id"], "priority": priority(issue, config), "labelIds": []}
    if ctx["project"]:
        item["projectId"] = ctx["project"]["id"]
    if config.get("use_labels") and issue.get("type"):
        name = ctx.get("label_names_ko", {}).get(issue["type"], issue["type"])
        existing = find_label(ctx["labels"], name)
        if existing or apply:
            item["labelIds"] = [existing["id"] if existing else label_id(client, ctx, name)]
    return item


def mutate_issue(client, issue, item, ctx):
    linear = (issue.get("payload") or {}).get("linear") or {}
    if linear.get("id"):
        data = client.call("mutation($id:String!,$input:IssueUpdateInput!){issueUpdate(id:$id,input:$input){success issue{id identifier url}}}", {"id": linear["id"], "input": item})["issueUpdate"]
    else:
        item = {"teamId": ctx["team"]["id"], **item}
        data = client.call("mutation($input:IssueCreateInput!){issueCreate(input:$input){success issue{id identifier url}}}", {"input": item})["issueCreate"]
    if not data["success"] or not data["issue"]:
        raise LinearError("issue mutation failed")
    return data["issue"]


SYNC_FIELDS = ("synced_state", "synced_state_type", "synced_priority", "synced_title", "synced_labels", "synced_project")


def desired_snapshot(issue, state, level, ctx):
    labels = []
    if ctx and ctx.get("labels") is not None and issue.get("type") and ctx.get("use_labels"):
        name = ctx.get("label_names_ko", {}).get(issue["type"], issue["type"])
        label = find_label(ctx["labels"], name)
        labels = [label["id"] if label else "name:" + name]
    return {"synced_state": state["id"], "synced_state_type": state["type"],
            "synced_priority": level, "synced_title": f"[{issue['id']}] {issue.get('title', '')}",
            "synced_labels": sorted(labels), "synced_project": (ctx.get("project") or {}).get("id") if ctx else None}


def remote_snapshot(remote):
    return {"synced_state": remote["state"]["id"], "synced_state_type": remote["state"]["type"],
            "synced_priority": remote["priority"], "synced_title": remote["title"],
            "synced_labels": sorted(node["id"] for node in remote["labels"]["nodes"]),
            "synced_project": (remote.get("project") or {}).get("id")}


def record_snapshot(path, issue, values, when=None, remote=None):
    snapshot = (issue.get("status"), issue.get("priority"), issue.get("title"), issue.get("type"), issue.get("updated_at"))
    def change(current):
        linear = current.setdefault("payload", {}).setdefault("linear", {})
        if remote:
            linear.update({k: remote[k] for k in ("id", "identifier", "url")})
        if (current.get("status"), current.get("priority"), current.get("title"), current.get("type"), current.get("updated_at")) == snapshot:
            linear.update(values)
            if when is not None:
                linear["synced_at"] = iso(when)
        else:
            for key in ("synced_at", *SYNC_FIELDS):
                linear.pop(key, None)
        return True
    return registry_transaction(path, issue["id"], change)


def record_push(path, issue, remote, values, when):
    return record_snapshot(path, issue, values, when, remote)


def record_pull(path, issue, remote, when):
    synced = timestamp((issue.get("payload") or {}).get("linear", {}).get("synced_at"))
    new_status = reverse_state(remote["state"], issue.get("status"))
    new_priority = REVERSE_PRIORITY.get(remote["priority"], None if remote["priority"] == 0 else issue.get("priority"))
    def change(current):
        if ((timestamp(current.get("updated_at")) and synced and timestamp(current["updated_at"]) > synced)
                or (current.get("status"), current.get("priority")) != (issue.get("status"), issue.get("priority"))):
            return False
        before = {"status": current.get("status"), "priority": current.get("priority")}
        current["status"], current["priority"] = new_status, new_priority
        current["updated_at"] = iso(when)
        linear = current.setdefault("payload", {}).setdefault("linear", {})
        linear.update(remote_snapshot(remote))
        linear["synced_at"] = iso(when)
        linear.setdefault("pulled_changes", []).append({"at": iso(when), "from": before, "to": {"status": new_status, "priority": new_priority}})
        return True
    return registry_transaction(path, issue["id"], change)


def plan_issue(issue, remote, ctx, config):
    linear = (issue.get("payload") or {}).get("linear") or {}
    state = find_state(issue.get("status", ""), ctx["states"], config)
    if not state:
        raise LinearError("workflow state unavailable")
    level = priority(issue, config)
    if not linear.get("id"):
        return "create", state, level
    synced = timestamp(linear.get("synced_at"))
    remote_changed = remote and synced and timestamp(remote.get("updatedAt")) and timestamp(remote["updatedAt"]) > synced and (remote["state"]["id"] != linear.get("synced_state") or remote["priority"] != linear.get("synced_priority"))
    if remote_changed:
        local_changed = timestamp(issue.get("updated_at")) and timestamp(issue["updated_at"]) > synced
        return ("conflict" if local_changed else "pull"), state, level
    desired = desired_snapshot(issue, state, level, ctx)
    baseline = remote_snapshot(remote) if any(key not in linear for key in SYNC_FIELDS) else {key: linear[key] for key in SYNC_FIELDS}
    return ("unchanged" if desired == baseline else "update"), state, level


def run(config, registry_path=REGISTRY, client=None, apply=False, push_only=False, pull_only=False, limit=None, now=None):
    now = now or utcnow()
    registry = read_registry(registry_path)
    targets, omitted = target_issues(registry, config, now, limit)
    result = {"mode": "apply" if apply else "dry-run", "key_needed": client is None, "team": None, "project_name": config["project_name"], "selected": len(targets), "omitted_by_limit": omitted, "counts": {k: 0 for k in ("create", "update", "unchanged", "pull", "conflict", "failed")}, "items": [], "conflicts": [], "warnings": []}
    if omitted:
        result["warnings"].append(f"{omitted} issues omitted by max_open_issues/limit")
    if not client:
        for issue in targets:
            action = "update" if (issue.get("payload") or {}).get("linear", {}).get("id") else "create"
            if (pull_only and action == "create") or (push_only and action == "pull"):
                continue
            result["counts"][action] += 1
            result["items"].append({"id": issue["id"], "action": action, "state": state_category(issue.get("status", ""), config), "priority": priority(issue, config)})
        result["warnings"].append("Linear API key needed for remote lookup and mapping")
        return result
    try:
        ctx = context(client, config)
    except (KeyError, TypeError) as exc:
        result["warnings"].append("Linear metadata lookup failed: " + type(exc).__name__)
        result["counts"]["failed"] = len(targets)
        return result
    result["team"] = {"key": ctx["team"]["key"], "name": ctx["team"]["name"]}
    ctx["use_labels"] = config.get("use_labels")
    if apply and not pull_only and not ctx["project"]:
        try:
            create_project(client, ctx, config)
        except (LinearError, KeyError, TypeError) as exc:
            result["warnings"].append("Project creation failed: " + type(exc).__name__)
            result["counts"]["failed"] = len(targets)
            return result
    for issue in targets:
        linked = (issue.get("payload") or {}).get("linear") or {}
        if pull_only and not linked.get("id"):
            continue
        try:
            remote = fetch_issue(client, linked["id"]) if linked.get("id") else None
            if linked.get("id") and not remote:
                raise LinearError("linked issue missing")
            action, state, level = plan_issue(issue, remote, ctx, config)
            if push_only and action == "pull":
                action = "update"
            if pull_only and action not in ("pull", "conflict"):
                continue
            result["counts"][action] += 1
            result["items"].append({"id": issue["id"], "action": action, "state": state["name"], "priority": level})
            if action == "conflict":
                result["conflicts"].append(issue["id"])
            if not apply:
                continue
            if action == "unchanged":
                if any(key not in linked for key in SYNC_FIELDS):
                    record_snapshot(registry_path, issue, desired_snapshot(issue, state, level, ctx))
                continue
            if action == "pull":
                if not record_pull(registry_path, issue, remote, now):
                    result["conflicts"].append(issue["id"])
                    result["counts"]["pull"] -= 1
                    result["counts"]["conflict"] += 1
                    item = issue_input(issue, config, ctx, client, True)
                    pushed = mutate_issue(client, issue, item, ctx)
                    record_push(registry_path, issue, pushed, desired_snapshot(issue, state, level, ctx), now)
            else:
                item = issue_input(issue, config, ctx, client, True)
                pushed = mutate_issue(client, issue, item, ctx)
                record_push(registry_path, issue, pushed, desired_snapshot(issue, state, level, ctx), now)
        except (LinearError, KeyError, TypeError, ValueError, OSError) as exc:
            result["counts"]["failed"] += 1
            result["items"].append({"id": issue["id"], "action": "failed", "reason": type(exc).__name__})
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--push-only", action="store_true")
    group.add_argument("--pull-only", action="store_true")
    parser.add_argument("--limit", type=int)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    if args.limit is not None and args.limit < 0:
        parser.error("--limit must be nonnegative")
    key = load_key()
    result = run(load_config(), client=GraphQLClient(key) if key else None, apply=args.apply and bool(key), push_only=args.push_only, pull_only=args.pull_only, limit=args.limit)
    if args.apply and not key:
        result["warnings"].append("--apply ignored: API key needed")
    # This report is intentionally limited to metadata, never credentials or payloads.
    (HERE / "last_run.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    display = {**result, "items": result["items"][:20]}
    if args.json:
        print(json.dumps(display, indent=2, ensure_ascii=False))
    else:
        print(f"Linear sync {result['mode']}: selected={result['selected']} omitted={result['omitted_by_limit']}")
        team = result["team"]
        print(f"Team: {team['key']} ({team['name']})" if team else "Team: unavailable (API key needed)")
        print(f"Project: {result['project_name']}")
        print(" ".join(f"{k}={v}" for k, v in result["counts"].items()))
        for item in display["items"]:
            print(f"  {item['id']}: {item['action']} ({item.get('state', '')}, priority={item.get('priority', '')})")
        for warning in result["warnings"]:
            print("Warning: " + warning)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
