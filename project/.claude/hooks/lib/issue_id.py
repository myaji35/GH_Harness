"""Shared issue ID allocation and registry sequence validation."""

from __future__ import annotations

from collections import Counter
import re
from typing import Any


_ISSUE_ID_RE = re.compile(r"^ISS-(\d+)$")


def _issues(registry: dict[str, Any]) -> list[Any]:
    issues = registry.get("issues", [])
    return issues if isinstance(issues, list) else []


def _total_issues(registry: dict[str, Any]) -> int:
    stats = registry.get("stats", {})
    total = stats.get("total_issues", 0) if isinstance(stats, dict) else 0
    return total if isinstance(total, int) and not isinstance(total, bool) else 0


def next_id(registry: dict[str, Any]) -> str:
    """Return the next unpadded ``ISS-N`` ID without mutating *registry*.

    Only canonical IDs matching ``^ISS-(\\d+)$`` contribute a numeric value.
    Historical suffixes such as ``-dup2`` are deliberately ignored.
    """
    ids: list[str] = []
    nums: list[int] = []
    for issue in _issues(registry):
        if not isinstance(issue, dict):
            continue
        issue_id = issue.get("id")
        if not isinstance(issue_id, str):
            continue
        ids.append(issue_id)
        match = _ISSUE_ID_RE.fullmatch(issue_id)
        if match:
            nums.append(int(match.group(1)))

    number = max(max(nums, default=0), _total_issues(registry)) + 1
    existing = set(ids)
    while f"ISS-{number}" in existing:
        number += 1
    return f"ISS-{number}"


def validate_sequence(registry: dict[str, Any]) -> list[str]:
    """Return non-blocking registry integrity findings."""
    problems: list[str] = []
    issue_ids: list[str] = []

    for index, issue in enumerate(_issues(registry)):
        issue_id = issue.get("id") if isinstance(issue, dict) else None
        if isinstance(issue_id, str):
            issue_ids.append(issue_id)
        if not isinstance(issue_id, str) or not _ISSUE_ID_RE.fullmatch(issue_id):
            problems.append(f"non-standard issue ID at issues[{index}]: {issue_id!r}")

    for issue_id, count in sorted(Counter(issue_ids).items()):
        if count > 1:
            problems.append(f"duplicate issue ID: {issue_id} ({count} occurrences)")

    actual = len(_issues(registry))
    stats = registry.get("stats", {})
    reported = stats.get("total_issues") if isinstance(stats, dict) else None
    if reported != actual:
        problems.append(
            f"stats.total_issues mismatch: reported {reported!r}, actual {actual}"
        )

    return problems


def _self_test() -> None:
    normal = {
        "issues": [{"id": "ISS-1"}, {"id": "ISS-002"}],
        "stats": {"total_issues": 2},
    }
    assert next_id(normal) == "ISS-3"
    assert validate_sequence(normal) == []

    manual_jump = {
        "issues": [{"id": "ISS-1"}, {"id": "ISS-1313"}],
        "stats": {"total_issues": 2},
    }
    assert next_id(manual_jump) == "ISS-1314"
    assert validate_sequence(manual_jump) == []

    duplicate = {
        "issues": [{"id": "ISS-1"}, {"id": "ISS-1"}],
        "stats": {"total_issues": 2},
    }
    assert next_id(duplicate) == "ISS-3"
    assert any("duplicate issue ID" in item for item in validate_sequence(duplicate))

    mixed = {
        "issues": [{"id": "ISS-1"}, {"id": "ISS-9999-dup2"}, {"id": "ISS-2"}],
        "stats": {"total_issues": 2},
    }
    assert next_id(mixed) == "ISS-3"
    mixed_problems = validate_sequence(mixed)
    assert any("non-standard issue ID" in item for item in mixed_problems)
    assert any("stats.total_issues mismatch" in item for item in mixed_problems)


if __name__ == "__main__":
    _self_test()
    print("issue_id.py self-test: PASS")
