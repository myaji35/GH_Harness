# graphify semantic layer

graphify `graph.json`을 벡터 캐시로 증분 임베딩하고 시맨틱 검색을 제공하는 harness 래퍼.
graphify pip 패키지를 수정하지 않음. 표준 라이브러리만 사용.

## 사전 조건

Ollama가 로컬에서 실행 중이고 임베딩 모델이 설치되어 있어야 한다.

```bash
# Ollama 설치 후
ollama pull nomic-embed-text
```

Ollama가 없으면 시맨틱 기능은 자동으로 skip되고 BFS 폴백이 작동한다. 파이프라인은 중단되지 않는다.

## 첫 임베딩 수동 실행

```bash
# 프로젝트 루트에서
python3 .claude/graphify/semantic/vector_cache.py \
  .claude/graphify/graphify-out/graph.json \
  .claude/graphify/semantic/.vector_cache.json
```

출력 예:
```json
{"embedded": 42, "reused": 0, "tombstoned": 0, "skipped_no_ollama": false}
```

이후 autobuild hook이 graph.json 갱신 시마다 자동으로 증분 임베딩한다.

## 시맨틱 쿼리

```bash
python3 .claude/graphify/semantic/semantic_query.py \
  .claude/graphify/semantic/.vector_cache.json \
  "인증 관련 모듈" \
  --top-k 5
```

Ollama 없음 → `{"fallback": "bfs", "reason": "ollama_unavailable"}` 출력 후 exit 0.

## autobuild 연동 동작

`graphify-autobuild.sh`가 session/change 신호 처리 후 시맨틱 스텝을 자동 실행한다:

- `graph.json` 존재 + Ollama 실행 중 → 증분 임베딩 실행
- 둘 중 하나라도 없음 → 1줄 로그 후 skip, exit 0

로그 위치: `.claude/graphify/autobuild.log`
