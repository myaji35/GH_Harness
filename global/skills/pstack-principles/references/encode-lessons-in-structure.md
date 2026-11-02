# 교훈을 구조에 새긴다 (Encode Lessons in Structure)

> 언제: 같은 지시를 두 번째로 쓰고 있거나, 같은 교정이 반복될 때.

같은 지시를 또 쓰게 되면 글을 더 늘리지 말고 규칙을 **lint·메타데이터 플래그·런타임 검사·스크립트**로 새긴다. (원문 frontmatter 설명)

교훈이 판단을 요구해서 구조로 새길 수 없다면, 지시를 더 눈에 띄게 만들고 실패 사례 예시를 붙인다.

**따름정리:** 고칠 방법이 구조적이라면 구조적 수정만 쓴다. 지시문은 증상이다.

하네스 연결: 반복 교정은 hook·게이트(예: on_complete 의 proof 게이트, secret-guard)로 옮기는 것이 이 원칙이다. hook·스크립트 변경은 코드이므로 Codex 위임 규칙을 따른다. CLAUDE.md·메모리에 규칙을 적는 것은 구조화가 불가능할 때의 차선책이다.

> 참고: 원문 본문은 이 두 문단뿐이다(원본 그대로).

---

## 영어 원문 (open-pstack `principle-encode-lessons-in-structure`, 그대로)

원문의 상대 링크(`../principle-*/SKILL.md`)는 이 스킬에서 `references/<원칙이름>.md` 에 해당한다.

````markdown
---
name: principle-encode-lessons-in-structure
description: "Apply when you catch yourself writing the same instruction a second time, or notice a recurring correction. Encode the rule as a lint, metadata flag, runtime check, or script instead of more text."
user-invocable: false
---

# Encode Lessons in Structure

If the lesson needs judgment and cannot be encoded, make the instruction more prominent and add an example of the failure mode.

**Corollary:** If the fix is structural, only use the structural fix. The instruction is the symptom.
````
