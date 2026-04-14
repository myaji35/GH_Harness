# LLM Wiki Lane (GH_Harness)

## 목적
Karpathy LLM Wiki 방식 — PDCA 리포트·인시던트·의사결정 로그를 Markdown vault로 축적.
**코드 그래프는 Graphify가 담당, 여긴 "왜"를 남기는 레인.**

## 구조
```
docs/
├─ llm-wiki/
│  ├─ decisions/     # 아키텍처·제품 의사결정 (ADR 경량)
│  ├─ incidents/     # 인시던트 보고서 (기존 파일 이주 대상)
│  ├─ pdca/          # PDCA phase 로그
│  └─ glossary/      # 도메인 용어 (보험·커뮤니티·자격증)
```

## 활용
- Claude Code가 `docs/llm-wiki/` 를 Obsidian-style로 질의 가능
- Phase 3에서 `docs/incident-report-*.md` 를 `incidents/` 로 이관

## Graphify와의 분업
| 질문 | 담당 |
|---|---|
| "이 함수 어디서 호출?" | Graphify |
| "왜 이 구조로 결정?" | LLM Wiki |
| "과거 비슷한 맹점?" | LLM Wiki (incidents) |
| "변경 영향 범위?" | Graphify |
