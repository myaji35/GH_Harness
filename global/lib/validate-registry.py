#!/usr/bin/env python3
"""registry.json 스키마 무결성 검증 — harness 파이프라인 안정성 게이트.

검사 항목 (실용 최소, Karpathy #2):
  1. 필수 필드: id, type, title, status, priority
  2. status enum 유효성
  3. priority enum 유효성
  4. id 중복 없음
  5. blocked_by 참조 무결성 (존재하지 않는 이슈 참조 금지)

사용:  python3 validate-registry.py <registry.json>
종료코드: 0=정상, 1=위반(상세 출력)
"""
import json
import sys

VALID_STATUS = {
    "READY", "IN_PROGRESS", "COMPLETED", "DONE", "FAILED",
    "BLOCKED", "AWAITING_USER", "GATE_PENDING", "CLOSED", "OBSOLETED",
}
VALID_PRIORITY = {"P0", "P1", "P2", "P3"}
REQUIRED_FIELDS = ("id", "type", "title", "status", "priority")


def validate(path):
    with open(path) as f:
        registry = json.load(f)

    issues = registry.get("issues", [])
    errors = []
    ids = set()

    for i, iss in enumerate(issues):
        ref = iss.get("id", f"<index {i}>")
        for field in REQUIRED_FIELDS:
            if field not in iss:
                errors.append(f"{ref}: 필수 필드 누락 '{field}'")
        st = iss.get("status")
        if st is not None and st not in VALID_STATUS:
            errors.append(f"{ref}: 잘못된 status '{st}'")
        pr = iss.get("priority")
        if pr is not None and pr not in VALID_PRIORITY:
            errors.append(f"{ref}: 잘못된 priority '{pr}'")
        iid = iss.get("id")
        if iid in ids:
            errors.append(f"{ref}: 중복 id")
        if iid:
            ids.add(iid)

    # blocked_by 참조 무결성 (모든 id 수집 후 검사)
    for iss in issues:
        ref = iss.get("id", "?")
        for dep in iss.get("payload", {}).get("blocked_by", []) or []:
            if dep not in ids:
                errors.append(f"{ref}: blocked_by가 존재하지 않는 이슈 참조 '{dep}'")

    if errors:
        print(f"❌ registry 검증 실패 ({len(errors)}건):")
        for e in errors:
            print(f"  - {e}")
        return 1
    print(f"✅ registry 검증 통과 ({len(issues)}개 이슈)")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: validate-registry.py <registry.json>", file=sys.stderr)
        sys.exit(2)
    sys.exit(validate(sys.argv[1]))
