"""
S2+S3 통합 테스트 — 5개 성공기준 검증
실행: python .claude/graphify/semantic/test_s2s3.py
"""

import copy
import importlib
import json
import sys
import tempfile
import traceback
from pathlib import Path
from unittest.mock import patch

# semantic 패키지를 직접 sys.path로 참조
_SEMANTIC_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(_SEMANTIC_DIR))

import vector_cache as vc  # noqa: E402  (local module)

_FIXTURE = _SEMANTIC_DIR / "fixtures" / "graph.json"

# 테스트용 768차원 더미 벡터
_DUMMY_VEC = [0.01 * i for i in range(768)]

BASE_NODES = [
    {"id": f"n{i}", "label": f"Node{i}", "source_file": ""}
    for i in range(1, 6)
]


def _write_graph(tmp_dir: Path, nodes: list) -> Path:
    p = tmp_dir / "graph.json"
    p.write_text(json.dumps({"nodes": nodes, "edges": []}), encoding="utf-8")
    return p


def _load_entries(cache_path: Path) -> dict:
    return json.loads(cache_path.read_text())["entries"]


def test_case1_first_build(tmp_path):
    """5노드 첫 build → embedded=5, 각 entry에 768차원 vector"""
    g = _write_graph(tmp_path, BASE_NODES)
    cache_path = tmp_path / ".vector_cache.json"

    with patch.object(vc, "ollama_available", return_value=True), \
         patch.object(vc, "embed_text", return_value=_DUMMY_VEC):
        r = vc.build_cache(g, cache_path)

    assert r["embedded"] == 5, f"expected embedded=5, got {r}"
    assert r["reused"] == 0
    assert r["skipped_no_ollama"] is False

    entries = _load_entries(cache_path)
    assert len(entries) == 5
    for nid, entry in entries.items():
        assert len(entry["vector"]) == 768, f"{nid} vector dim wrong"
        assert entry["tombstone"] is False
    print(f"[PASS] case1: embedded={r['embedded']}, reused={r['reused']}, dim=768")


def test_case2_reuse_on_same_graph(tmp_path):
    """동일 graph.json 재build → embedded=0, reused=5 (Ollama 호출 0회)"""
    g = _write_graph(tmp_path, BASE_NODES)
    cache_path = tmp_path / ".vector_cache.json"

    embed_call_count = 0

    def counting_embed(text):
        nonlocal embed_call_count
        embed_call_count += 1
        return _DUMMY_VEC

    with patch.object(vc, "ollama_available", return_value=True), \
         patch.object(vc, "embed_text", side_effect=counting_embed):
        vc.build_cache(g, cache_path)   # 1차
        embed_call_count = 0
        r = vc.build_cache(g, cache_path)  # 2차

    assert r["embedded"] == 0, f"expected embedded=0, got {r}"
    assert r["reused"] == 5, f"expected reused=5, got {r}"
    assert embed_call_count == 0, f"embed 호출 없어야 함: {embed_call_count}회"
    print(f"[PASS] case2: embedded={r['embedded']}, reused={r['reused']}, embed_calls={embed_call_count}")


def test_case3_label_changed(tmp_path):
    """노드 1개 label 변경 후 재build → embedded=1, reused=4"""
    g = _write_graph(tmp_path, BASE_NODES)
    cache_path = tmp_path / ".vector_cache.json"

    with patch.object(vc, "ollama_available", return_value=True), \
         patch.object(vc, "embed_text", return_value=_DUMMY_VEC):
        vc.build_cache(g, cache_path)

        modified = copy.deepcopy(BASE_NODES)
        modified[2]["label"] = "ChangedNode3"
        g2 = _write_graph(tmp_path, modified)
        r = vc.build_cache(g2, cache_path)

    assert r["embedded"] == 1, f"expected embedded=1, got {r}"
    assert r["reused"] == 4, f"expected reused=4, got {r}"
    print(f"[PASS] case3: embedded={r['embedded']}, reused={r['reused']}")


def test_case4_node_removed_tombstone(tmp_path):
    """노드 1개 제거 후 재build → 해당 node_id tombstone=true"""
    g = _write_graph(tmp_path, BASE_NODES)
    cache_path = tmp_path / ".vector_cache.json"

    with patch.object(vc, "ollama_available", return_value=True), \
         patch.object(vc, "embed_text", return_value=_DUMMY_VEC):
        vc.build_cache(g, cache_path)

        reduced = [n for n in BASE_NODES if n["id"] != "n5"]
        g2 = _write_graph(tmp_path, reduced)
        r = vc.build_cache(g2, cache_path)

    assert r["tombstoned"] == 1, f"expected tombstoned=1, got {r}"
    entries = _load_entries(cache_path)
    assert entries["n5"]["tombstone"] is True, "n5 should be tombstoned"
    for nid in ["n1", "n2", "n3", "n4"]:
        assert entries[nid]["tombstone"] is False
    print(f"[PASS] case4: tombstoned={r['tombstoned']}, n5.tombstone=True")


def test_case5_no_ollama(tmp_path):
    """ollama_available=False → skipped_no_ollama=True, 기존 캐시 보존"""
    g = _write_graph(tmp_path, BASE_NODES)
    cache_path = tmp_path / ".vector_cache.json"

    with patch.object(vc, "ollama_available", return_value=True), \
         patch.object(vc, "embed_text", return_value=_DUMMY_VEC):
        vc.build_cache(g, cache_path)

    entries_before = _load_entries(cache_path)

    with patch.object(vc, "ollama_available", return_value=False):
        r = vc.build_cache(g, cache_path)

    assert r["skipped_no_ollama"] is True, f"expected True, got {r}"
    entries_after = _load_entries(cache_path)
    assert entries_before == entries_after, "캐시 변경 불가"
    print(f"[PASS] case5: skipped_no_ollama={r['skipped_no_ollama']}, cache preserved")


if __name__ == "__main__":
    tests = [
        test_case1_first_build,
        test_case2_reuse_on_same_graph,
        test_case3_label_changed,
        test_case4_node_removed_tombstone,
        test_case5_no_ollama,
    ]

    passed = 0
    failed = 0
    for fn in tests:
        with tempfile.TemporaryDirectory() as td:
            try:
                fn(Path(td))
                passed += 1
            except Exception as e:
                print(f"[FAIL] {fn.__name__}: {e}")
                traceback.print_exc()
                failed += 1

    print(f"\n{'='*40}")
    print(f"결과: {passed} PASSED / {failed} FAILED")
    sys.exit(0 if failed == 0 else 1)
