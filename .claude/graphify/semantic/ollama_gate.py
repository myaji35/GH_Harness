"""
graphify semantic layer — S1: Ollama 게이트 + 임베딩 파이프라인
새 파일은 harness 리포 내 래퍼로만 존재. graphifyy pip 패키지 수정 금지.

표준 라이브러리만 사용 (urllib.request). 외부 의존성 없음.
"""

import json
import urllib.request
import urllib.error

_OLLAMA_BASE = "http://localhost:11434"
_EMBED_MODEL = "nomic-embed-text"
_TIMEOUT = 2  # 초


def ollama_available() -> bool:
    """Ollama가 실행 중이고 nomic-embed-text 모델이 있으면 True. 예외 없음."""
    try:
        req = urllib.request.Request(f"{_OLLAMA_BASE}/api/tags")
        with urllib.request.urlopen(req, timeout=_TIMEOUT) as resp:
            data = json.loads(resp.read())
        models = [m.get("name", "") for m in data.get("models", [])]
        return any(_EMBED_MODEL in name for name in models)
    except Exception:
        return False


def embed_text(text: str) -> list[float] | None:
    """
    text를 nomic-embed-text로 임베딩. 768차원 벡터 반환.
    게이트 실패 또는 오류 시 None 반환 (파이프라인 중단하지 않음).
    """
    if not ollama_available():
        return None
    try:
        payload = json.dumps({"model": _EMBED_MODEL, "prompt": text}).encode()
        req = urllib.request.Request(
            f"{_OLLAMA_BASE}/api/embeddings",
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
        return data.get("embedding")
    except Exception:
        return None
