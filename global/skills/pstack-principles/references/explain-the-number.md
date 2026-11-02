# 숫자를 설명한다 (Explain the Number)

> 언제: 직접 잰 숫자(속도 향상, 회귀, 처리량, 지연, 평가 결과)를 믿거나 보고하거나 그에 따라 행동하기 전.

그 숫자를 제한하는 것이 무엇인지 찾고, 내가 생각하는 작업이 아닌 다른 것을 잰 것은 아닌지 배제한다.

- **"왜 두 배가 아니지?"를 묻는다.** 결과의 상한을 정한 자원이나 코드 경로(코어, 락, 디스크, 네트워크, 부하 발생기 자체)를 이름으로 댄다. 실행 중에 뜬 프로파일이나 시스템 카운터에서 찾아 소스에 대응시킨다. 코드를 읽고 짐작한 것은 제한 요인이 아니다. 숫자가 왜 두 배 좋지 않은지 말할 수 없다면, 무엇을 쟀는지 모르는 것이다.
- **그 숫자가 달리 무엇을 재고 있을 수 있는지 적고, 하나씩 증거로 배제한다.** 단골 용의자: 에러, 건너뛰었거나 캐시된 작업, 실행되지 않은 코드, 튜닝 안 된 쪽(기본 설정으로 둔 비교 대상), 노이즈, 전체로 보면 의미 없을 만큼 작은 조각.
- **증거를 숫자와 같이 둔다.** 실행 횟수, 편차, 제한 요인을 노트나 연결된 산출물에 적는다.

성능 숫자라면 원문의 benchmark-checklist 절차를 따른다(하네스에는 이 스킬이 없으니 위 세 항목을 체크리스트로 쓴다). 평가 결과라면 시행(trial)에도 같은 질문을 한다: 모든 실행이 실제로 과제를 했나, 차이가 시행·모델이 바뀌어도 유지되나, 시나리오가 의미 있나.

숫자 뒤의 증거에 실행 횟수·편차·제한 요인이 없거나, 아낀 시간이 바뀐 조각이 원래 걸리던 시간보다 크다면 이 원칙을 건너뛴 것이다.

[증명한다](prove-it-works.md)와 다르다 — 그쪽은 산출물이 진짜인지 확인한다.

## 하네스 적용 (현재 단계)
- **on_complete 게이트로 들어갔다(2026-11-03, ISS-345).** SCORE·RUN_TESTS·COVERAGE_CHECK·REGRESSION_CHECK·BIZ_VALIDATE 등 수치 이슈의 result 에 score·coverage·pass_rate·speedup·latency_ms 같은 숫자가 있으면 `result.number_sources.<키>` 에 그 숫자를 낸 측정 명령이나 결과 파일을 적어야 한다. 예: `{"score":82,"number_sources":{"score":"npm run eval > eval.json"}}`. 지금은 `HARNESS_NUMBER_MODE` 기본 warn(경고만, proof-metrics.jsonl 에 number-warn 기록), 2주 측정 후 enforce(완료 거부)로 올린다. 수치를 고르기 전 점검은 `benchmark-checklist` 스킬.
- 지금은 규칙으로 쓴다: **대표님께 수치를 보고할 때는 그 수치를 낸 측정 명령과 출처 파일(source)을 같이 적는다.** 예: `점수 82 — 측정: npm run eval -- --runs 5 (편차 ±2), 출처: .claude/eval/score.json`.
- 명령·출처를 댈 수 없는 수치는 "추정"이라고 밝힌다.

---

## 영어 원문 (open-pstack `principle-explain-the-number`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-explain-the-number
description: "Apply before you trust, report, or act on a number you measured: a speedup, a regression, a throughput, a latency, or an eval result. Find what limits it, and rule out that it measured something other than the work you think."
user-invocable: false
---

# Explain the Number

- **Ask "why not double?"** Name the resource or code path that bounds the result, such as a core, a lock, the disk, the network, or the load generator itself. Get it from a profile or from system counters taken during a run, then map it to source. A guess from reading the code is not a limiter. If you cannot say why the number is not twice as good, you do not know what you measured.
- **List what else the number could be measuring, and rule out each one with evidence.** The usual suspects are errors, skipped or cached work, code that never ran, an untuned side (one left on default settings), noise, and a piece too small to matter end to end.
- **Keep the evidence with the number.** Put the run count, the spread, and the limiter in the notes or a linked artifact.

For a performance number, run the full procedure with the [benchmark-checklist](../benchmark-checklist/SKILL.md) skill. For an eval result, ask the same of the trials: did every run do the task, does the gap hold across trials and models, and does the scenario matter.

You skipped this when the evidence behind a number has no run count, no spread, or no named limiter, or when the time saved is larger than the time the changed piece took.

Distinct from [Prove It Works](../principle-prove-it-works/SKILL.md), which checks that an output is real.
````
