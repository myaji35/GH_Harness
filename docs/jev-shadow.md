# Jev 섀도 모드 (ISS-536)

intent-gate(키워드 규칙)와 나란히 TypeSafe Jev의 판정을 기록해 비교한다. **Jev 결과는 판정에 쓰지 않는다.**

## 구조
- `intent-gate.sh` — 판정 사유(`question`/`harness_meta`/`meta_exclude`/`short`/`no_work_verb`/`dup`/`work`)와 마스킹된 발화를 `~/.claude/jev-shadow/queue.jsonl`에 쌓고, `jev-shadow.sh`를 분리 프로세스로 띄운다. 훅 지연 +15ms 실측.
- `jev-shadow.sh` — 대기열을 Jev API로 판정해 `results.jsonl`에 기록한다. 1회 최대 50건. 실패는 `errors.log`에만 남고 결과를 꾸미지 않는다.
- 저장 위치는 저장소 밖(`~/.claude/`)이다. 발화 원문이 공개 저장소에 커밋되지 않게 하려는 것이다.

## 키 (둘 중 하나)
| 키 | 경로 | model |
|---|---|---|
| `KSS_TYPESAFE_API_KEY` | `https://api.typesafe.ai` (직접) | `jev-latest` |
| `KSS_AI_GATEWAY_API_KEY` | `https://ai-gateway.vercel.sh/typesafe` (Vercel AI Gateway, TypeSafe 호환 API) | `typesafe-ai/jev` |

- 환경변수 또는 `/Volumes/E_SSD/02_GitHub.nosync/.env`에서 읽는다. 둘 다 있으면 직접 경로를 쓴다.
- 키가 없으면 API를 호출하지 않고 대기열만 쌓는다(`errors.log`에 하루 1회 `no_key`).
- TypeSafe 직접 가입은 2026-09-24 기준 마감이라 Gateway 경로를 추가했다(ISS-538). Gateway에서 `jev-latest`를 쓰면 Model not found가 나므로 `typesafe-ai/jev`를 쓴다.
- `jevmodel.org`는 공식 도메인이 아니다. 키를 입력하지 않는다.

## 명령
```bash
bash .claude/hooks/jev-shadow.sh           # 대기열 처리
bash .claude/hooks/jev-shadow.sh report    # 혼동행렬·신뢰도 구간·불일치·비용
```
- 끄기: `JEV_SHADOW=0`
- 다른 디렉터리: `JEV_SHADOW_DIR=<dir>`
- 테스트 서버: `TYPESAFE_API_BASE=<url>`

## 한국어 오프라인 평가 (200건)
- `~/.claude/jev-shadow-eval/`에 과거 발화 200건(24개 프로젝트, 층화 표본)의 규칙 판정과 정답 라벨(`labels.jsonl`)이 준비돼 있다.
- 라벨은 Sonnet이 붙였고, Opus가 표본 20건을 대조했을 때 18건이 일치했다.
- 키를 발급받은 뒤 아래를 실행한다. 비용은 1센트 미만이다.
```bash
for i in 1 2 3 4; do JEV_SHADOW_DIR=~/.claude/jev-shadow-eval bash .claude/hooks/jev-shadow.sh; done
JEV_SHADOW_DIR=~/.claude/jev-shadow-eval bash .claude/hooks/jev-shadow.sh report
```

## 기준선 (2026-09-24, 규칙 단독)
정답 work 73건 중 규칙이 잡은 것은 13건이다(재현율 17.8%, 정밀도 68.4%, 2분류 정확도 67.0%). 놓친 이유는 WORK 동사 없음 37건, 12자 미만 12건, 메타 제외 6건, dup 3건(ISS-537)이다.

## 도입 판정 기준
- Jev의 `jev_conf >= 0.99` 구간 정확도가 규칙보다 높고, 커버리지가 30% 이상이면 보조 판정 도입을 검토한다.
- 한국어 정확도가 규칙 기준선보다 낮으면 도입하지 않는다.
