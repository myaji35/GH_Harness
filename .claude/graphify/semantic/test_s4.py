"""
S4 시맨틱 쿼리 검증 테스트.

성공 기준 5개:
  1. Ollama 실행 중 + fixtures 캐시 → 의미상 가장 가까운 노드가 Top-1
  2. --top-k 3 → 정확히 3개 반환
  3. tombstone 노드 결과 제외
  4. ollama_available() False monkeypatch → None 반환, 예외 없음
  5. 순수 Python 코사인 유사도: 동일 벡터끼리 cosine≈1.0
"""

import json
import os
import sys
import math
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

# 경로 설정
_DIR = Path(__file__).parent
sys.path.insert(0, str(_DIR))

from semantic_query import semantic_search, _cosine  # noqa: E402


_FIXTURES_CACHE = _DIR / "fixtures" / ".vector_cache.json"


class TestCosine(unittest.TestCase):
    """기준 5: 순수 Python 코사인 유사도 정확성."""

    def test_identical_vectors(self):
        v = [1.0, 0.5, -0.3, 0.8]
        self.assertAlmostEqual(_cosine(v, v), 1.0, places=6)

    def test_orthogonal_vectors(self):
        a = [1.0, 0.0]
        b = [0.0, 1.0]
        self.assertAlmostEqual(_cosine(a, b), 0.0, places=6)

    def test_zero_vector(self):
        self.assertEqual(_cosine([0.0, 0.0], [1.0, 2.0]), 0.0)

    def test_opposite_vectors(self):
        v = [1.0, 2.0, 3.0]
        neg = [-1.0, -2.0, -3.0]
        self.assertAlmostEqual(_cosine(v, neg), -1.0, places=6)


class TestSemanticSearch(unittest.TestCase):
    """기준 1~4: semantic_search() 동작."""

    def setUp(self):
        if not _FIXTURES_CACHE.exists():
            self.skipTest("fixtures/.vector_cache.json 없음 — build_cache 먼저 실행")

    # ── 기준 4: ollama 없을 때 None 반환 ──────────────────────────────────────
    def test_fallback_when_ollama_unavailable(self):
        with patch("semantic_query.ollama_available", return_value=False):
            result = semantic_search(str(_FIXTURES_CACHE), "planning system")
        self.assertIsNone(result, "ollama 불가 시 None 반환해야 함")

    # ── 기준 2: top-k 개수 ────────────────────────────────────────────────────
    def test_top_k_count(self):
        results = semantic_search(str(_FIXTURES_CACHE), "planning system", top_k=3)
        if results is None:
            self.skipTest("Ollama 미실행")
        self.assertEqual(len(results), 3, f"top-k=3이어야 하지만 {len(results)}개 반환")

    # ── 기준 1: 의미상 Top-1 정확성 ──────────────────────────────────────────
    def test_top1_relevance_ollama(self):
        """
        "issue registry" 쿼리 → IssueRegistry(n4)가 Top-1 이어야 한다.
        의미상 "issue"/"registry"와 가장 가깝기 때문.
        """
        results = semantic_search(str(_FIXTURES_CACHE), "issue registry", top_k=5)
        if results is None:
            self.skipTest("Ollama 미실행")
        self.assertTrue(len(results) > 0)
        top1 = results[0]
        print(f"\n[Top-1] node_id={top1['node_id']} label={top1['label']} cosine={top1['cosine']:.4f}")
        # 반드시 IssueRegistry(n4)여야 함
        self.assertEqual(
            top1["node_id"], "n4",
            f"'issue registry' 쿼리의 Top-1은 IssueRegistry(n4)여야 함. 실제: {top1}"
        )
        # cosine이 최대값
        for other in results[1:]:
            self.assertGreaterEqual(
                top1["cosine"], other["cosine"],
                "Top-1 cosine이 최고여야 함"
            )

    # ── 기준 3: tombstone 제외 ────────────────────────────────────────────────
    def test_tombstone_excluded(self):
        """캐시에 tombstone=True 노드를 주입하면 결과에서 제외되어야 함."""
        cache_data = json.loads(_FIXTURES_CACHE.read_text(encoding="utf-8"))

        # n1에 tombstone 추가 (원본 수정 없이 임시 복사본 사용)
        import copy
        modified = copy.deepcopy(cache_data)
        modified["entries"]["n1"]["tombstone"] = True

        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".json", delete=False, encoding="utf-8"
        ) as f:
            json.dump(modified, f)
            tmp_path = f.name

        try:
            results = semantic_search(tmp_path, "harness system", top_k=5)
            if results is None:
                self.skipTest("Ollama 미실행")
            node_ids = [r["node_id"] for r in results]
            self.assertNotIn("n1", node_ids, "tombstone n1이 결과에 포함되면 안 됨")
            print(f"\n[tombstone test] 반환 node_ids: {node_ids}")
        finally:
            os.unlink(tmp_path)


if __name__ == "__main__":
    unittest.main(verbosity=2)
