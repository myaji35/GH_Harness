import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HOOKS = Path(__file__).resolve().parents[1]


class OwnerDigestTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.registry = self.root / ".claude/issue-db/registry.json"
        self.registry.parent.mkdir(parents=True)
        self.env = {**os.environ, "HOME": str(self.root)}

    def tearDown(self):
        self.temp.cleanup()

    def save(self, issues):
        self.registry.write_text(json.dumps({"issues": issues}), encoding="utf-8")

    def run_hook(self, name, *args, input_text=None):
        command = ["python3", str(HOOKS / name)] if name.endswith(".py") else ["bash", str(HOOKS / name)]
        return subprocess.run(command + list(args), cwd=self.root, env=self.env, input=input_text,
                              capture_output=True, text=True, check=False)

    def issue(self, number, status="READY", title="작업", origin=None, progress=None):
        payload = {}
        if origin:
            payload["origin"] = origin
        if progress:
            payload["progress"] = progress
        return {"id": f"ISS-{number}", "status": status, "title": title, "priority": "P1",
                "created_at": "2026-10-01T00:00:00+09:00", "payload": payload}

    def test_digest_groups_automated_and_progress(self):
        self.save([self.issue(1, "AWAITING_USER", "[결정필요] 결정"),
                   self.issue(2, title="[아이디어] 제안", origin="intent-gate:idea"),
                   self.issue(3, title="[지시] 구현", progress={"at": "2026-10-10T00:00:00+09:00", "done": "설계", "next": "구현"}),
                   self.issue(4, title="[Plan: 자동] 세부"), self.issue(5, origin="self"),
                   self.issue(6, origin="restored-from-linear"), self.issue(7, status="DONE")])
        result = self.run_hook("owner-digest.py")
        self.assertEqual(result.returncode, 0)
        for fragment in ("열린 이슈 6건", "대표님 답을 기다리는 것", "아이디어로만 남은 것",
                         "지시했는데 아직 안 끝난 것", "ISS-1", "ISS-2", "ISS-3",
                         "↳ 어디까지: 설계 / 다음: 구현", "기계 자동 파생 이슈 3건"):
            self.assertIn(fragment, result.stdout)
        self.assertNotIn("ISS-4", result.stdout)
        self.assertNotIn("[지시] 구현", result.stdout)

    def test_empty_and_bad_registry_print_nothing(self):
        self.save([self.issue(1, status="DONE")])
        self.assertEqual(self.run_hook("owner-digest.py").stdout, "")
        self.registry.write_text("{", encoding="utf-8")
        self.assertEqual(self.run_hook("owner-digest.py").stdout, "")

    def test_progress_note_records_and_updates(self):
        self.save([self.issue(1)])
        result = self.run_hook("progress-note.sh", "ISS-1", "검토 완료", "배포")
        self.assertEqual(result.returncode, 0, result.stderr)
        saved = json.loads(self.registry.read_text(encoding="utf-8"))["issues"][0]
        self.assertEqual(saved["payload"]["progress"]["done"], "검토 완료")
        self.assertEqual(saved["payload"]["progress"]["next"], "배포")
        self.assertEqual(saved["updated_at"], saved["payload"]["progress"]["at"])
        self.assertIsNotNone(dt.datetime.fromisoformat(saved["updated_at"]).tzinfo)
        self.assertEqual(self.run_hook("progress-note.sh", "ISS-9", "완료", "다음").returncode, 1)
        self.assertEqual(self.run_hook("progress-note.sh", "ISS-1").returncode, 2)

    def test_progress_guard_blocks_once_and_skips_active_stop(self):
        issue = self.issue(1, status="IN_PROGRESS")
        issue["payload"]["session_id"] = "session-one"
        self.save([issue])
        hook = json.dumps({"session_id": "session-one", "stop_hook_active": False})
        first = self.run_hook("progress-guard.sh", input_text=hook)
        self.assertEqual(first.returncode, 0)
        self.assertEqual(json.loads(first.stdout)["decision"], "block")
        self.assertIn("ISS-1", json.loads(first.stdout)["reason"])
        self.assertEqual(self.run_hook("progress-guard.sh", input_text=hook).stdout, "")
        self.assertEqual(self.run_hook("progress-guard.sh", input_text=json.dumps({"session_id": "session-two", "stop_hook_active": True})).stdout, "")
        self.assertEqual(self.run_hook("progress-guard.sh", input_text="broken").stdout, "")

    def test_progress_guard_respects_recent_record_and_blocks_stale_record(self):
        issue = self.issue(2, status="IN_PROGRESS")
        issue["payload"]["session_id"] = "session-two"
        issue["payload"]["progress"] = {"at": dt.datetime.now().astimezone().isoformat(), "done": "진행", "next": "계속"}
        self.save([issue])
        hook = json.dumps({"session_id": "session-two", "stop_hook_active": False})
        self.assertEqual(self.run_hook("progress-guard.sh", input_text=hook).stdout, "")
        issue["payload"]["progress"]["at"] = "2020-01-01T00:00:00+09:00"
        self.save([issue])
        self.assertEqual(json.loads(self.run_hook("progress-guard.sh", input_text=hook).stdout)["decision"], "block")


if __name__ == "__main__":
    unittest.main()
