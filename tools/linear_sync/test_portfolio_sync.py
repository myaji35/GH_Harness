import datetime as dt
import json
from pathlib import Path
import tempfile
import unittest

from tools.linear_sync import linear_sync as sync
from tools.linear_sync import portfolio_sync as portfolio


NOW = dt.datetime(2026, 10, 7, tzinfo=dt.timezone.utc)


def issue(number, status="READY", priority="P2"):
    return {"id": f"ISS-{number}", "title": "한글 제목", "status": status, "priority": priority,
            "type": "FIX_BUG", "created_at": "2026-10-01T00:00:00Z", "updated_at": "2026-10-01T00:00:00Z",
            "payload": {"ref": "로컬", "raw_prompt": "SECRET", "evidence": "SECRET"}}


class FakeClient:
    def __init__(self, active=0, projects=None, states=None, labels=None):
        self.active = active
        self.projects = projects if projects is not None else []
        self.states = states if states is not None else [
            {"id": "b", "name": "Backlog", "type": "backlog"},
            {"id": "u", "name": "Todo", "type": "unstarted"},
            {"id": "s", "name": "In Progress", "type": "started"},
            {"id": "r", "name": "In Review", "type": "started"},
            {"id": "d", "name": "Done", "type": "completed"},
            {"id": "c", "name": "Canceled", "type": "canceled"},
        ]
        self.labels = labels if labels is not None else [{"id": "label", "name": "버그 수정", "team": {"id": "team"}}]
        self.mutations = []

    def call(self, query, variables=None):
        variables = variables or {}
        if "teams(" in query:
            nodes = [{"id": "team", "key": "HAR", "name": "가가호호 개발"}]
            return {"teams": {"nodes": nodes, "pageInfo": {"hasNextPage": False}}}
        if "workflowStates(" in query:
            nodes = [{**s, "team": {"id": "team"}} for s in self.states]
            return {"workflowStates": {"nodes": nodes, "pageInfo": {"hasNextPage": False}}}
        if "projects(" in query:
            nodes = [{**p, "teams": {"nodes": [{"id": "team"}]}} for p in self.projects]
            return {"projects": {"nodes": nodes, "pageInfo": {"hasNextPage": False}}}
        if "issueLabels(" in query:
            return {"issueLabels": {"nodes": self.labels, "pageInfo": {"hasNextPage": False}}}
        if "issues(" in query:
            nodes = [{"id": str(i), "state": {"type": "started"}} for i in range(self.active)]
            nodes += [{"id": "done", "state": {"type": "completed"}}]
            return {"issues": {"nodes": nodes, "pageInfo": {"hasNextPage": False}}}
        if "issue(id:" in query:
            return {"issue": {"id": variables["id"], "identifier": "HAR-1", "url": "https://example.test/1",
                              "updatedAt": "2026-10-01T00:00:00Z", "title": "[ISS-1] 한글 제목", "priority": 3,
                              "state": self.states[1], "project": {"id": "p"}, "labels": {"nodes": [{"id": "label"}]}}}
        self.mutations.append((query, variables))
        if "teamUpdate(" in query:
            return {"teamUpdate": {"success": True}}
        if "workflowStateUpdate(" in query:
            return {"workflowStateUpdate": {"success": True}}
        if "issueLabelUpdate(" in query:
            next(label for label in self.labels if label["id"] == variables["id"])["name"] = variables["input"]["name"]
            return {"issueLabelUpdate": {"success": True}}
        if "projectCreate(" in query:
            return {"projectCreate": {"success": True, "project": {"id": "new", **variables["input"]}}}
        if "projectUpdate(" in query:
            return {"projectUpdate": {"success": True}}
        if "issueCreate(" in query:
            return {"issueCreate": {"success": True, "issue": {"id": "new-issue", "identifier": "HAR-2", "url": "https://example.test/2"}}}
        if "issueUpdate(" in query:
            return {"issueUpdate": {"success": True, "issue": {"id": variables["id"], "identifier": "HAR-1", "url": "https://example.test/1"}}}
        raise AssertionError(query)


class PortfolioTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.config = {"base_dir": str(self.base), "team_key": "HAR", "team_name_ko": "가가호호 개발",
                       "active_issue_cap": 4, "per_project_quota": 2, "done_window_days": 14,
                       "state_names_ko": portfolio.load_portfolio()["state_names_ko"],
                       "label_names_ko": portfolio.load_portfolio()["label_names_ko"],
                       "workspace_label_renames": portfolio.load_portfolio()["workspace_label_renames"],
                       "projects": [{"dir": x, "name": x, "summary": x} for x in ("a", "b", "c")]}

    def tearDown(self):
        self.temp.cleanup()

    def registry(self, name, issues):
        path = self.base / name / ".claude/issue-db/registry.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"issues": issues}), encoding="utf-8")

    def test_round_robin_and_quota(self):
        linked = issue(90)
        linked["payload"]["linear"] = {"id": "linked"}
        self.registry("a", [linked] + [issue(i) for i in range(1, 5)])
        self.registry("b", [issue(i) for i in range(5, 9)])
        self.registry("c", [issue(i) for i in range(9, 13)])
        result = portfolio.run(self.config, FakeClient(), now=NOW)
        self.assertEqual([r["counts"]["create"] for r in result["projects"]], [1, 2, 1])
        self.assertEqual(result["omitted_by_budget"], 8)
        self.assertEqual(result["projects"][0]["counts"]["update"], 1)

    def test_cap_exceeded_creates_nothing(self):
        self.registry("a", [issue(1)])
        (self.base / "b").mkdir()
        result = portfolio.run(self.config, FakeClient(active=5), now=NOW)
        self.assertEqual(result["active_issues"], 5)
        self.assertEqual(result["projects"][0]["counts"]["create"], 0)
        self.assertEqual(result["omitted_by_budget"], 1)

    def test_active_count_includes_other_team_and_all_pages(self):
        class Paged:
            def call(self, query, variables=None):
                if not variables["after"]:
                    return {"issues": {"nodes": [{"state": {"type": "started"}},
                                                 {"state": {"type": "completed"}}],
                                       "pageInfo": {"hasNextPage": True, "endCursor": "next"}}}
                return {"issues": {"nodes": [{"state": {"type": "backlog"}},
                                             {"state": {"type": "canceled"}}],
                                   "pageInfo": {"hasNextPage": False, "endCursor": None}}}
        self.assertEqual(portfolio.active_count(Paged()), 2)

    def test_state_localization_idempotent(self):
        fake = FakeClient()
        ctx = portfolio.metadata(fake, self.config)
        portfolio.localize_team(fake, ctx, self.config, True, [])
        first = len(fake.mutations)
        self.assertEqual(first, len(fake.states))
        portfolio.localize_team(fake, ctx, self.config, True, [])
        self.assertEqual(len(fake.mutations), first)

    def test_reserved_duplicate_state_is_silent(self):
        fake = FakeClient(states=[{"id": "dup", "name": "Duplicate", "type": "duplicate"},
                                  {"id": "b", "name": "Backlog", "type": "backlog"}])
        ctx = portfolio.metadata(fake, self.config)
        warnings = []
        portfolio.localize_team(fake, ctx, self.config, False, warnings)
        self.assertFalse(any("Duplicate" in warning for warning in warnings))
        portfolio.localize_team(fake, ctx, self.config, True, warnings)
        self.assertEqual([variables["id"] for query, variables in fake.mutations if "workflowStateUpdate(" in query], ["b"])
        self.assertEqual(ctx["states"][0]["name"], "Duplicate")

    def test_existing_target_state_skips_rename_without_warning(self):
        states = [{"id": "found", "name": "발견", "type": "backlog"},
                  {"id": "backlog", "name": "백로그", "type": "backlog"},
                  {"id": "refine", "name": "다듬음", "type": "unstarted"},
                  {"id": "todo", "name": "할 일", "type": "unstarted"},
                  {"id": "extra", "name": "Extra", "type": "triage"},
                  {"id": "target", "name": "rEvIeW", "type": "triage"}]
        config = {**self.config, "state_names_ko": {**self.config["state_names_ko"], "triage": "Review"}}
        fake = FakeClient(states=states)
        ctx = portfolio.metadata(fake, config)
        warnings = []
        portfolio.localize_team(fake, ctx, config, False, warnings)
        portfolio.localize_team(fake, ctx, config, True, warnings)
        self.assertEqual(fake.mutations, [])
        self.assertEqual(warnings, [])

    def test_workspace_label_renames_dry_run_apply_and_repeat(self):
        labels = [{"id": "w", "name": "Feature", "team": None},
                  {"id": "t", "name": "Bug", "team": {"id": "team"}},
                  {"id": "already", "name": "개선", "team": {"id": "team"}},
                  {"id": "other", "name": "Improvement", "team": {"id": "other"}},
                  {"id": "lower", "name": "feature", "team": {"id": "team"}}]
        fake = FakeClient(labels=labels)
        ctx = portfolio.metadata(fake, self.config)
        warnings = []
        portfolio.rename_workspace_labels(fake, ctx, self.config, False, warnings)
        self.assertEqual(warnings, ["라벨 이름 변경 예정: Feature → 기능", "라벨 이름 변경 예정: Bug → 버그"])
        self.assertEqual(fake.mutations, [])
        portfolio.rename_workspace_labels(fake, ctx, self.config, True, warnings)
        updates = [(variables["id"], variables["input"]["name"]) for query, variables in fake.mutations if "issueLabelUpdate(" in query]
        self.assertEqual(updates, [("w", "기능"), ("t", "버그")])
        self.assertEqual([label["name"] for label in ctx["labels"]], ["기능", "버그", "개선", "feature"])
        portfolio.rename_workspace_labels(fake, ctx, self.config, True, warnings)
        self.assertEqual(len(fake.mutations), 2)

    def test_run_applies_label_renames_only_in_apply_mode(self):
        config = {**self.config, "projects": []}
        fake = FakeClient(labels=[{"id": "feature", "name": "Feature", "team": None}])
        planned = portfolio.run(config, fake, now=NOW)
        self.assertIn("라벨 이름 변경 예정: Feature → 기능", planned["warnings"])
        self.assertFalse(any("issueLabelUpdate(" in query for query, _ in fake.mutations))
        applied = portfolio.run(config, fake, apply=True, now=NOW)
        self.assertEqual(applied["mode"], "apply")
        self.assertEqual(fake.labels[0]["name"], "기능")
        self.assertEqual(sum("issueLabelUpdate(" in query for query, _ in fake.mutations), 1)
        portfolio.run(config, fake, apply=True, now=NOW)
        self.assertEqual(sum("issueLabelUpdate(" in query for query, _ in fake.mutations), 1)

    def test_portfolio_config_has_common_korean_labels(self):
        names = portfolio.load_portfolio()["label_names_ko"]
        self.assertEqual({key: names[key] for key in ("FEATURE", "BUG", "IMPROVEMENT", "DOCS", "CHORE", "TEST")},
                         {"FEATURE": "기능", "BUG": "버그", "IMPROVEMENT": "개선", "DOCS": "문서", "CHORE": "잡무", "TEST": "테스트"})

    def test_project_create_update_unchanged_and_alias(self):
        fake = FakeClient(projects=[{"id": "old", "name": "legacy", "description": "old"}])
        ctx = portfolio.metadata(fake, self.config)
        spec = {"dir": "a", "name": "한글", "summary": "설명", "linear_project_alias": "legacy"}
        project, action = portfolio.ensure_project(fake, ctx, spec, False)
        self.assertEqual((project["id"], action), ("old", "update"))
        project, action = portfolio.ensure_project(fake, ctx, spec, True)
        self.assertEqual(action, "update")
        self.assertEqual(fake.mutations[-1][1]["input"]["description"], portfolio.project_description(spec))
        self.assertEqual(portfolio.ensure_project(fake, ctx, spec, True)[1], "unchanged")
        self.assertEqual(portfolio.ensure_project(fake, ctx, {"dir": "b", "name": "새", "summary": "새"}, False)[1], "create")

    def test_missing_registry_creates_project_without_issues(self):
        (self.base / "a").mkdir()
        result = portfolio.run(self.config, FakeClient(), now=NOW)
        self.assertEqual(result["projects"][0]["project_action"], "create")
        self.assertEqual(result["projects"][0]["counts"]["create"], 0)
        self.assertIn("레지스트리 없음", result["projects"][0]["warnings"][0])

    def test_korean_states_and_allowlist(self):
        states = [{"id": "b", "name": "백로그", "type": "backlog"},
                  {"id": "u", "name": "할 일", "type": "unstarted"},
                  {"id": "s", "name": "진행 중", "type": "started"},
                  {"id": "r", "name": "검토 중", "type": "started"}]
        config = sync.load_config()
        self.assertEqual(sync.find_state("READY", states, config)["id"], "b")
        self.assertEqual(sync.find_state("IN_PROGRESS", states, config)["id"], "s")
        self.assertEqual(sync.find_state("AWAITING_USER", states, config)["id"], "r")
        self.assertEqual(sync.reverse_state(states[3], "AWAITING_USER"), "AWAITING_USER")
        self.assertEqual(sync.reverse_state(states[2], "READY"), "IN_PROGRESS")
        text = portfolio.issue_description(issue(1), self.config["projects"][0])
        self.assertIn("프로젝트: a (a)", text)
        self.assertNotIn("SECRET", text)
        client = FakeClient(states=states)
        ctx = {"states": states, "project": {"id": "p"}, "team": {"id": "team"},
               "labels": [{"id": "label", "name": "버그 수정"}], "use_labels": True,
               "label_names_ko": self.config["label_names_ko"]}
        spec = {**self.config["projects"][0], "label_names_ko": self.config["label_names_ko"]}
        item = sync.issue_input(issue(1), config, ctx, client, False,
                                description_text=portfolio.issue_description(issue(1), spec))
        self.assertEqual((item["projectId"], item["labelIds"]), ("p", ["label"]))
        self.assertIn("유형: 버그 수정", item["description"])
        self.assertNotIn("SECRET", item["description"])


if __name__ == "__main__":
    unittest.main()
