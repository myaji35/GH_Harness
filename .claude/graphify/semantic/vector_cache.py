"""
graphify semantic layer — S2+S3: 벡터 캐시 스키마 + 증분 임베딩
별도 .vector_cache.json에 저장. graph.json은 읽기만 한다.
표준 라이브러리만 사용 (hashlib, json, os, pathlib).
"""

import hashlib
import json
import os
from pathlib import Path

try:
    from .ollama_gate import ollama_available, embed_text
except ImportError:
    from ollama_gate import ollama_available, embed_text  # type: ignore[no-redef]

_SCHEMA_VERSION = "1.0"
_MODEL = "nomic-embed-text"
_DIM = 768


def _load_cache(cache_path: Path) -> dict:
    if cache_path.exists():
        try:
            return json.loads(cache_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            pass
    return {
        "_schema_version": _SCHEMA_VERSION,
        "_model": _MODEL,
        "_dim": _DIM,
        "entries": {},
    }


def _save_cache(cache: dict, cache_path: Path) -> None:
    cache_path.write_text(json.dumps(cache, ensure_ascii=False, indent=2), encoding="utf-8")


def content_hash(node: dict) -> str:
    """sha256(label + source_file + str(file_mtime)). file_mtime는 source_file 존재 시만."""
    label = node.get("label", "")
    source_file = node.get("source_file", "")
    mtime = ""
    if source_file:
        try:
            mtime = str(os.path.getmtime(source_file))
        except OSError:
            pass
    raw = label + source_file + mtime
    return hashlib.sha256(raw.encode()).hexdigest()


def build_cache(graph_json_path: str | Path, cache_path: str | Path) -> dict:
    """
    graph.json 노드를 읽어 .vector_cache.json을 증분 갱신한다.

    반환:
      {"embedded": N, "reused": M, "tombstoned": K, "skipped_no_ollama": bool}
    """
    graph_json_path = Path(graph_json_path)
    cache_path = Path(cache_path)

    graph = json.loads(graph_json_path.read_text(encoding="utf-8"))
    nodes = graph.get("nodes", [])

    has_ollama = ollama_available()
    cache = _load_cache(cache_path)
    entries = cache.setdefault("entries", {})

    embedded = 0
    reused = 0
    tombstoned = 0
    skipped_no_ollama = not has_ollama

    live_ids = {node["id"] for node in nodes}

    # 사라진 노드 → tombstone (hard delete 금지)
    for node_id, entry in entries.items():
        if node_id not in live_ids and not entry.get("tombstone", False):
            entry["tombstone"] = True
            tombstoned += 1

    for node in nodes:
        node_id = node["id"]
        h = content_hash(node)
        existing = entries.get(node_id)

        # 캐시 hit — hash 동일하면 skip
        if existing and existing.get("hash") == h and not existing.get("tombstone", False):
            reused += 1
            continue

        if not has_ollama:
            # Ollama 없음 — 캐시 보존, 임베딩 건너뜀
            continue

        vec = embed_text(node.get("label", ""))
        if vec is None:
            # embed_text 실패 — 보존
            continue

        entries[node_id] = {
            "hash": h,
            "vector": vec,
            "label": node.get("label", ""),
            "tombstone": False,
        }
        embedded += 1

    _save_cache(cache, cache_path)

    return {
        "embedded": embedded,
        "reused": reused,
        "tombstoned": tombstoned,
        "skipped_no_ollama": skipped_no_ollama,
    }


# ── CLI ───────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import sys

    if len(sys.argv) < 3:
        print(
            "Usage: python3 vector_cache.py <graph_json_path> <cache_json_path>",
            file=sys.stderr,
        )
        sys.exit(1)

    result = build_cache(sys.argv[1], sys.argv[2])
    import json as _json
    print(_json.dumps(result))
