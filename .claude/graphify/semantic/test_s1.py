"""S1 자체 검증 테스트 — 실행: python3 test_s1.py"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from ollama_gate import ollama_available, embed_text

PASS = "\033[32mPASS\033[0m"
FAIL = "\033[31mFAIL\033[0m"


def check(label: str, cond: bool) -> bool:
    print(f"  [{PASS if cond else FAIL}] {label}")
    return cond


def main() -> int:
    results = []
    print("\n=== S1 Ollama 게이트 + 임베딩 검증 ===\n")

    # 1. 게이트 확인
    gate = ollama_available()
    results.append(check(f"ollama_available() == True (현재값: {gate})", gate is True))

    # 2. 정상 임베딩 케이스
    vec = embed_text("hello world")
    results.append(check("embed_text 반환값이 None이 아님", vec is not None))
    if vec is not None:
        results.append(check(f"벡터 차원 == 768 (실제: {len(vec)})", len(vec) == 768))
        results.append(check("벡터 요소가 float", all(isinstance(v, float) for v in vec[:5])))
    else:
        results.append(check("벡터 차원 == 768 (skip: vec=None)", False))
        results.append(check("벡터 요소 float (skip)", False))

    # 3. 게이트 False 시 None 반환 (monkeypatch)
    import ollama_gate as _mod
    _orig = _mod.ollama_available
    _mod.ollama_available = lambda: False
    none_result = embed_text("test")
    _mod.ollama_available = _orig
    results.append(check("게이트 False 시 embed_text → None", none_result is None))

    total = len(results)
    passed = sum(results)
    print(f"\n결과: {passed}/{total} PASS\n")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
