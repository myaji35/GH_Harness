# 동작을 증명한다 (Prove It Works)

> 언제: 작업을 마친 뒤, 완료를 선언하기 전.

모든 작업 산출물을 **진짜를 직접 확인해서** 검증한다. 대리 지표, 자기 보고, "컴파일된다"로 추론하지 않는다.

**왜:** 검증 안 된 작업은 정확성을 모른다. 간접 검증(파일 수정 시각, 출력의 신선도, 에이전트 자기 보고, 캐시된 스크린샷)이 직접 관찰보다 싸 보인다. 틀린 추론에 따라 행동하는 비용이 원본을 확인하는 비용보다 훨씬 크다.

대리 지표가 아니라 진짜를 확인한다:
- 파생 상태로 간접 확인하지 말고 프로세스 생존을 직접 확인한다.
- 캐시되거나 파생된 표현이 아니라 실제 값을 읽는다.
- 검증이 실패하면 시스템보다 먼저 관찰 방법을 의심한다.

## 가능하면 점검을 스크립트로

가장 강한 증명은 한 번 눈으로 본 것이 아니라 같은 비교를 다시 돌리는 결정적 스크립트다. 스크립트를 쓰고(코드이므로 Codex 위임), 돌리고, 그 출력을 검수자가 다시 돌릴 수 있는 산출물로 남긴다.

산출물은 대표님이 볼 수 있게 둔다(가능하면 브라우저로 띄운다 — 전역 규칙). 대규모 포팅·마이그레이션처럼 나중에 감사 가능한 기록이 필요한 큰 작업일 때만 커밋한다(`show-me-your-work` 스킬).

## 하네스 연결 — 이미 게이트로 강제 중
- 코드를 바꾼 이슈는 `on_complete.sh` 가 **`result.proof` 배열 `[{"cmd","exit_code","output"}]` 없이는 DONE 으로 받지 않는다**(거부). 예: `"proof":[{"cmd":"npm test -- auth","exit_code":0,"output":"Tests: 12 passed"}]`.
- Codex 의 "완료" 보고는 proof 가 아니다. 내가 직접 실행한 명령·종료코드·출력만 proof 다.
- UI·CLI·서비스 동작 증명 경로가 없으면 `create-verification-skill` 로 프로젝트 검증 스킬을 먼저 만든다.

---

## 영어 원문 (open-pstack `principle-prove-it-works`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-prove-it-works
description: "Apply after completing a task, before declaring done. Verify against the real artifact (run the feature, read the actual value, inspect the diff), not a proxy, self-report, or 'it compiles.'"
user-invocable: false
---

# Prove It Works

Verify every task output by checking the real thing directly. Do not infer from proxies, self-reports, or "it compiles."

**Why:** Unverified work has unknown correctness. Indirect verification (file mtimes, output freshness, agent self-reports, cached screenshots) feels cheaper than direct observation. Acting on a wrong inference costs far more than checking the source.

Check the real thing, not a proxy:
- Check process liveness directly, not indirectly through derived state
- Read the actual value, not a cached or derived representation
- When verification fails, suspect the observation method before suspecting the system

## Script the check when you can

The strongest proof is a deterministic script that re-runs the same comparison, not a one-time eyeball. Write the script, run it, and keep its output as an artifact a reviewer can re-run instead of trusting your word.

Keep the artifact visible for the human. Commit it only for large or complex work where the trail has to be auditable later, like a big port or migration (the **show-me-your-work** skill).
````
