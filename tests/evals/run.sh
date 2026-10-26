#!/usr/bin/env bash
# GH_Harness 골든 평가 — global/policy/REVIEW.md §5. 하네스를 바꾼 뒤 반드시 돌린다.
exec python3 "$(dirname "${BASH_SOURCE[0]}")/run.py" "$@"
