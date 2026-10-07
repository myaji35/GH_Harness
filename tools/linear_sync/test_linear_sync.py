import copy
from contextlib import redirect_stdout
import datetime as dt
from io import BytesIO, StringIO
import json
from pathlib import Path
import tempfile
import unittest
import urllib.error
from unittest.mock import patch

from tools.linear_sync import linear_sync as sync


NOW = dt.datetime(2026, 10, 5, tzinfo=dt.timezone.utc)
STATES = [
    {"id": "b", "name": "Backlog", "type": "backlog"},
    {"id": "u", "name": "Todo", "type": "unstarted"},
    {"id": "s", "name": "In Progress", "type": "started"},
    {"id": "r", "name": "In Review", "type": "started"},
    {"id": "d", "name": "Done", "type": "completed"},
    {"id": "c", "name": "Canceled", "type": "canceled"},
]
CONFIG = {"team_key": None, "project_name": "GH_Harness", "done_window_days": 14, "max_open_issues": 220, "state_map": {"BACKLOG": "backlog", "READY": "unstarted", "IN_PROGRESS": "started", "AWAITING_USER": "In Review", "HANDED_OFF": "In Review", "PARTIAL": "In Review", "COMPLETED": "completed", "DONE": "completed", "CLOSED": "canceled"}, "priority_map": sync.PRIORITY_DEFAULT, "use_labels": True}


def issue(number, status="READY", priority="P2", updated="2026-10-01T00:00:00Z"):
    return {"id": f"ISS-{number}", "title": "Example", "status": status, "priority": priority, "type": "BUG", "created_at": updated, "updated_at": updated, "payload": {"ref": "safe", "raw_prompt": "SECRET", "evidence": "SECRET"}}


class FakeClient:
    def __init__(self, remote=None, teams=None):
        self.remote = remote or {}
        self.teams = teams if teams is not None else [{"id": "team", "key": "GH", "name": "Harness"}]
        self.mutations = []

    def call(self, query, variables=None):
        variables = variables or {}
        if "teams(" in query:
            return {"teams": {"nodes": self.teams, "pageInfo": {"hasNextPage": False, "endCursor": None}}}
        if "workflowStates(" in query:
            return {"workflowStates": {"nodes": [{**s, "team": {"id": "team"}} for s in STATES], "pageInfo": {"hasNextPage": False, "endCursor": None}}}
        if "projects(" in query:
            return {"projects": {"nodes": [{"id": "project", "name": "GH_Harness", "teams": {"nodes": [{"id": "team"}]}}], "pageInfo": {"hasNextPage": False, "endCursor": None}}}
        if "issueLabels(" in query:
            return {"issueLabels": {"nodes": [{"id": "label", "name": "BUG", "team": {"id": "team"}}], "pageInfo": {"hasNextPage": False, "endCursor": None}}}
        if "issue(id:" in query:
            return {"issue": self.remote.get(variables["id"])}
        if "issueUpdate(" in query:
            self.mutations.append(copy.deepcopy(variables))
            return {"issueUpdate": {"success": True, "issue": {"id": variables["id"], "identifier": "GH-1", "url": "https://linear.app/issue/GH-1"}}}
        if "issueCreate(" in query:
            self.mutations.append(copy.deepcopy(variables))
            return {"issueCreate": {"success": True, "issue": {"id": "linear-new", "identifier": "GH-2", "url": "https://linear.app/issue/GH-2"}}}
        raise AssertionError(query)


class SyncTests(unittest.TestCase):
    def test_timestamp_accepts_epoch_seconds_and_milliseconds(self):
        epoch = dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc)
        self.assertEqual(sync.timestamp(0), epoch)
        self.assertEqual(sync.timestamp(1_700_000_000), dt.datetime(2023, 11, 14, 22, 13, 20, tzinfo=dt.timezone.utc))
        self.assertEqual(sync.timestamp(1.5), epoch + dt.timedelta(seconds=1.5))
        self.assertEqual(sync.timestamp(1_700_000_000_000), sync.timestamp(1_700_000_000))
        self.assertEqual(sync.timestamp(1_000_000_000_000), dt.datetime(2001, 9, 9, 1, 46, 40, tzinfo=dt.timezone.utc))

    def test_timestamp_returns_none_for_invalid_values(self):
        for value in (None, True, [], {}, object(), "not a timestamp", float("nan"), float("inf"), 10**1000):
            with self.subTest(value=value):
                self.assertIsNone(sync.timestamp(value))

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "registry.json"

    def tearDown(self):
        self.tmp.cleanup()

    def save(self, issues):
        self.path.write_text(json.dumps({"issues": issues}), encoding="utf-8")

    def read(self):
        return sync.read_registry(self.path)["issues"]

    def linked(self, local, updated="2026-09-30T00:00:00Z"):
        local["payload"]["linear"] = {"id": "linear-1", "identifier": "GH-1", "url": "https://linear.app/issue/GH-1", "synced_at": "2026-10-01T00:00:00Z", "synced_state": "u", "synced_priority": 3}
        local["updated_at"] = updated
        return local

    def remote(self):
        return {"linear-1": {"id": "linear-1", "identifier": "GH-1", "url": "https://linear.app/issue/GH-1", "updatedAt": "2026-10-02T00:00:00Z", "title": "[ISS-1] Example", "priority": 2, "state": STATES[2], "project": {"id": "project"}, "labels": {"nodes": [{"id": "label"}]}}}

    def matching_remote(self, number):
        return {"id": f"linear-{number}", "identifier": f"GH-{number}", "url": f"https://linear.app/issue/GH-{number}",
                "updatedAt": "2026-10-01T00:00:00Z", "title": f"[ISS-{number}] Example", "priority": 3,
                "state": STATES[1], "project": {"id": "project"}, "labels": {"nodes": [{"id": "label"}]}}

    def test_repeated_push_skips_unchanged_and_updates_only_changed_state(self):
        locals_ = [self.linked(issue(number)) for number in (1, 2, 3)]
        for number, local in zip((1, 2, 3), locals_):
            local["payload"]["linear"].update({"id": f"linear-{number}", "identifier": f"GH-{number}"})
        self.save(locals_)
        fake = FakeClient({f"linear-{number}": self.matching_remote(number) for number in (1, 2, 3)})
        first = sync.run(CONFIG, self.path, fake, apply=True, now=NOW)
        self.assertEqual((first["counts"]["update"], first["counts"]["unchanged"]), (0, 3))
        self.assertEqual(fake.mutations, [])
        self.assertEqual([item["payload"]["linear"]["synced_at"] for item in self.read()], ["2026-10-01T00:00:00Z"] * 3)
        self.assertTrue(all("synced_title" in item["payload"]["linear"] for item in self.read()))
        second = sync.run(CONFIG, self.path, fake, apply=True, now=NOW + dt.timedelta(hours=1))
        self.assertEqual((second["counts"]["update"], second["counts"]["unchanged"]), (0, 3))
        self.assertEqual(fake.mutations, [])
        changed = self.read()
        changed[1]["status"] = "IN_PROGRESS"
        changed[1]["updated_at"] = "2026-10-05T01:00:00Z"
        self.save(changed)
        third = sync.run(CONFIG, self.path, fake, apply=True, now=NOW + dt.timedelta(hours=2))
        self.assertEqual((third["counts"]["update"], third["counts"]["unchanged"]), (1, 2))
        self.assertEqual(len(fake.mutations), 1)
        self.assertEqual(fake.mutations[0]["id"], "linear-2")
        self.assertEqual(fake.mutations[0]["input"]["stateId"], "s")
        self.assertEqual(self.read()[1]["payload"]["linear"]["synced_at"], "2026-10-05T02:00:00Z")

    def test_push_compares_title_priority_labels_and_project(self):
        for field, value in (("synced_title", "old title"), ("synced_priority", 2),
                             ("synced_labels", []), ("synced_project", "other"),
                             ("synced_state_type", "started")):
            with self.subTest(field=field):
                local = self.linked(issue(1))
                local["payload"]["linear"].update({"synced_title": "[ISS-1] Example", "synced_state_type": "unstarted",
                                                     "synced_labels": ["label"], "synced_project": "project"})
                local["payload"]["linear"][field] = value
                self.save([local])
                fake = FakeClient({"linear-1": self.matching_remote(1)})
                result = sync.run(CONFIG, self.path, fake, apply=True, now=NOW)
                self.assertEqual(result["counts"]["update"], 1)
                self.assertEqual(len(fake.mutations), 1)

    def test_targets_window_and_cap(self):
        issues = [issue(i, priority="P0" if i == 27 else "P3") for i in range(28)]
        recent = issue(28, "DONE")
        recent["completed_at"] = "2026-09-21T00:00:00Z"
        old = issue(29, "DONE", updated="2026-09-20T23:59:59Z")
        old["completed_at"] = "2026-09-20T23:59:59Z"
        issues += [recent, old]
        chosen, omitted = sync.target_issues({"issues": issues}, CONFIG, NOW)
        self.assertEqual(len(chosen), 29)
        self.assertEqual(omitted, 0)
        small = {**CONFIG, "max_open_issues": 10}
        chosen, omitted = sync.target_issues({"issues": issues}, small, NOW)
        self.assertEqual((len(chosen), omitted), (10, 19))
        self.assertEqual(chosen[0]["id"], "ISS-27")

    def test_mapping_and_description_allowlist(self):
        self.assertEqual(sync.find_state("AWAITING_USER", STATES, CONFIG)["id"], "r")
        self.assertEqual(sync.find_state("READY", STATES, CONFIG)["id"], "u")
        self.assertEqual(sync.find_state("CLOSED_INVALID", STATES, CONFIG)["id"], "c")
        self.assertEqual(sync.reverse_state(STATES[3], "PARTIAL"), "PARTIAL")
        self.assertEqual(sync.reverse_state(STATES[2], "PARTIAL"), "IN_PROGRESS")
        self.assertEqual(sync.priority(issue(1, priority="P0"), CONFIG), 1)
        self.assertEqual(sync.priority(issue(2, priority="P3"), CONFIG), 4)
        text = sync.description(issue(1))
        self.assertIn("ref: safe", text)
        self.assertNotIn("raw_prompt", text)
        self.assertNotIn("SECRET", text)

    def test_label_lookup_reuses_casefold_match_for_input_and_snapshot(self):
        fake = FakeClient()
        ctx = {"team": {"id": "team"}, "states": STATES, "project": None,
               "labels": [{"id": "feature", "name": "Feature"}], "use_labels": True}
        feature = issue(1)
        feature["type"] = "FEATURE"
        self.assertEqual(sync.label_id(fake, ctx, "FEATURE"), "feature")
        self.assertEqual(sync.issue_input(feature, CONFIG, ctx, fake, True)["labelIds"], ["feature"])
        self.assertEqual(sync.desired_snapshot(feature, STATES[1], 3, ctx)["synced_labels"], ["feature"])
        self.assertEqual(fake.mutations, [])
        self.assertEqual(sync.find_label([{"id": "unicode", "name": "Straße"}], "STRASSE")["id"], "unicode")

    def test_pull_applies_remote_change_and_history(self):
        self.save([self.linked(issue(1))])
        fake = FakeClient(self.remote())
        result = sync.run(CONFIG, self.path, fake, apply=True, now=NOW)
        actual = self.read()[0]
        self.assertEqual(result["counts"]["pull"], 1)
        self.assertEqual((actual["status"], actual["priority"]), ("IN_PROGRESS", "P1"))
        self.assertEqual(actual["payload"]["linear"]["synced_state"], "s")
        self.assertEqual(len(actual["payload"]["linear"]["pulled_changes"]), 1)
        self.assertEqual(fake.mutations, [])

    def test_conflict_registry_wins(self):
        self.save([self.linked(issue(1), "2026-10-01T12:00:00Z")])
        fake = FakeClient(self.remote())
        result = sync.run(CONFIG, self.path, fake, apply=True, now=NOW)
        actual = self.read()[0]
        self.assertEqual(result["counts"]["conflict"], 1)
        self.assertEqual(result["conflicts"], ["ISS-1"])
        self.assertEqual((actual["status"], actual["priority"]), ("READY", "P2"))
        self.assertEqual(fake.mutations[0]["input"]["stateId"], "u")
        self.assertEqual(fake.mutations[0]["input"]["priority"], 3)

    def test_dry_run_does_not_write_registry_or_mutate_linear(self):
        self.save([self.linked(issue(1))])
        before = self.path.read_bytes()
        fake = FakeClient(self.remote())
        result = sync.run(CONFIG, self.path, fake, now=NOW)
        self.assertEqual(result["counts"]["pull"], 1)
        self.assertEqual(result["team"], {"key": "GH", "name": "Harness"})
        self.assertEqual(result["project_name"], "GH_Harness")
        self.assertEqual(self.path.read_bytes(), before)
        self.assertEqual(fake.mutations, [])

    def test_configured_team_is_selected_even_when_it_is_not_first(self):
        self.save([issue(1)])
        fake = FakeClient(teams=[{"id": "other", "key": "GH", "name": "Other"}, {"id": "team", "key": "HAR", "name": "Harness"}])
        result = sync.run({**CONFIG, "team_key": "HAR"}, self.path, fake, now=NOW)
        self.assertEqual(result["team"], {"key": "HAR", "name": "Harness"})
        self.assertEqual(result["counts"]["create"], 1)

    def test_missing_configured_team_aborts_before_writes(self):
        self.save([issue(1)])
        before = self.path.read_bytes()
        fake = FakeClient()
        with self.assertRaises(sync.LinearError):
            sync.run({**CONFIG, "team_key": "HAR"}, self.path, fake, apply=True, now=NOW)
        self.assertEqual(fake.mutations, [])
        self.assertEqual(self.path.read_bytes(), before)

    def test_multiple_teams_without_team_key_aborts_before_writes(self):
        self.save([issue(1)])
        before = self.path.read_bytes()
        fake = FakeClient(teams=[{"id": "other", "key": "GH", "name": "Other"}, {"id": "team", "key": "HAR", "name": "Harness"}])
        with self.assertRaisesRegex(sync.LinearError, "team_key 를 config.json 에 지정하라"):
            sync.run(CONFIG, self.path, fake, apply=True, now=NOW)
        self.assertEqual(fake.mutations, [])
        self.assertEqual(self.path.read_bytes(), before)

    def test_main_text_and_json_include_team_and_project_without_api_key(self):
        self.save([issue(1)])
        fake = FakeClient(teams=[{"id": "team", "key": "HAR", "name": "Harness"}])
        config = {**CONFIG, "team_key": "HAR"}
        with patch.object(sync, "load_config", return_value=config), patch.object(sync, "load_key", return_value="test-secret"), patch.object(sync, "GraphQLClient", return_value=fake), patch.object(sync, "read_registry", return_value={"issues": [issue(1)]}), patch.object(sync, "HERE", self.path.parent):
            output = StringIO()
            with redirect_stdout(output):
                self.assertEqual(sync.main([]), 0)
            self.assertIn("Team: HAR (Harness)", output.getvalue())
            self.assertIn("Project: GH_Harness", output.getvalue())
            self.assertNotIn("test-secret", output.getvalue())
            output = StringIO()
            with redirect_stdout(output):
                self.assertEqual(sync.main(["--json"]), 0)
            summary = json.loads(output.getvalue())
            self.assertEqual(summary["team"], {"key": "HAR", "name": "Harness"})
            self.assertEqual(summary["project_name"], "GH_Harness")
            self.assertNotIn("test-secret", output.getvalue())
            self.assertNotIn("test-secret", (self.path.parent / "last_run.json").read_text())

    def test_push_records_link_without_exposing_payload(self):
        self.save([issue(1)])
        fake = FakeClient()
        result = sync.run(CONFIG, self.path, fake, apply=True, now=NOW)
        self.assertEqual(result["counts"]["create"], 1)
        self.assertEqual(self.read()[0]["payload"]["linear"]["id"], "linear-new")
        sent = fake.mutations[0]["input"]
        self.assertNotIn("SECRET", sent["description"])
        self.assertEqual(sent["labelIds"], ["label"])

    def test_graphql_client_retries_rate_limit(self):
        attempts = []
        class Response(BytesIO):
            pass
        def opener(request, timeout):
            attempts.append(request.headers["Authorization"])
            if len(attempts) == 1:
                raise urllib.error.HTTPError(request.full_url, 429, "rate limited", {}, None)
            return Response(b'{"data":{"ok":true}}')
        client = sync.GraphQLClient("test-secret", opener=opener, sleep=lambda _: None)
        self.assertEqual(client.call("query{ok}"), {"ok": True})
        self.assertEqual(attempts, ["test-secret", "test-secret"])


if __name__ == "__main__":
    unittest.main()
