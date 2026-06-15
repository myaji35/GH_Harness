"""
graphify semantic layer — S4: 시맨틱 쿼리
harness 래퍼 스크립트. graphify pip 패키지 수정 금지.
표준 라이브러리만 사용. numpy/requests 없음.

호출 형태:
  python3 .claude/graphify/semantic/semantic_query.py <cache_path> "<query>" [--top-k N]
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

try:
    from .ollama_gate import embed_text, ollama_available
    from .vector_cache import _load_cache
except ImportError:
    from ollama_gate import embed_text, ollama_available  # type: ignore[no-redef]
    from vector_cache import _load_cache  # type: ignore[no-redef]


# ── 순수 Python 코사인 유사도 ──────────────────────────────────────────────────

def _cosine(a: list[float], b: list[float]) -> float:
    """두 벡터의 코사인 유사도. 영벡터는 0.0 반환."""
    dot = sum(x * y for x, y in zip(a, b))
    norm_a = math.sqrt(sum(x * x for x in a))
    norm_b = math.sqrt(sum(y * y for y in b))
    if norm_a == 0.0 or norm_b == 0.0:
        return 0.0
    return dot / (norm_a * norm_b)


# ── 시맨틱 검색 ───────────────────────────────────────────────────────────────

def semantic_search(
    cache_path: str | Path,
    query: str,
    top_k: int = 5,
) -> list[dict] | None:
    """
    시맨틱 쿼리 실행.

    반환:
      Ollama 사용 불가 → None  (호출측이 BFS 폴백할 수 있도록)
      정상 → [{"node_id", "label", "cosine"}, ...] 유사도 내림차순 top_k개
    """
    if not ollama_available():
        return None

    query_vec = embed_text(query)
    if query_vec is None:
        return None

    cache = _load_cache(Path(cache_path))
    entries = cache.get("entries", {})

    scored: list[tuple[float, str, str]] = []  # (cosine, node_id, label)
    for node_id, entry in entries.items():
        if entry.get("tombstone", False):
            continue
        vec = entry.get("vector")
        if not vec:
            continue
        score = _cosine(query_vec, vec)
        scored.append((score, node_id, entry.get("label", "")))

    scored.sort(key=lambda x: x[0], reverse=True)

    return [
        {"node_id": node_id, "label": label, "cosine": round(cosine, 6)}
        for cosine, node_id, label in scored[:top_k]
    ]


# ── CLI ───────────────────────────────────────────────────────────────────────

def _parse_args(argv: list[str]) -> tuple[str, str, int]:
    """argv 파싱. 오류 시 sys.exit(1)."""
    if len(argv) < 3:
        print("Usage: semantic_query.py <cache_path> \"<query>\" [--top-k N]", file=sys.stderr)
        sys.exit(1)

    cache_path = argv[1]
    query = argv[2]
    top_k = 5

    i = 3
    while i < len(argv):
        if argv[i] == "--top-k" and i + 1 < len(argv):
            try:
                top_k = int(argv[i + 1])
            except ValueError:
                print(f"--top-k 값이 정수가 아닙니다: {argv[i+1]}", file=sys.stderr)
                sys.exit(1)
            i += 2
        else:
            i += 1

    return cache_path, query, top_k


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv

    cache_path, query, top_k = _parse_args(argv)

    results = semantic_search(cache_path, query, top_k)

    if results is None:
        # BFS 폴백 신호
        print(json.dumps({"fallback": "bfs", "reason": "ollama_unavailable"}))
        return 0

    if not results:
        print("(no results)")
        return 0

    # graphify query 출력과 유사한 형식 + Semantic 태그
    print(f"Semantic query: \"{query}\" | top-k={top_k}")
    print("-" * 52)
    for rank, item in enumerate(results, 1):
        print(
            f"  [{rank}] {item['node_id']:6s}  {item['label']:<30s}"
            f"  Semantic | cosine={item['cosine']:.4f}"
        )
    print()
    # 기계 판독용 JSON도 stdout에 추가 출력 (테스트 파싱용)
    print(json.dumps(results))
    return 0


if __name__ == "__main__":
    sys.exit(main())
