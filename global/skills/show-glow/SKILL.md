---
name: show-glow
description: 파일(특히 마크다운)을 터미널에서 glow로 예쁘게 렌더해 보여준다. 대표님이 "보여줘", "보여 줘", "/show", "glow로 보여줘", "이 파일 열어줘" 등으로 특정 파일/문서를 확인하고 싶어할 때 사용. glow 미설치 시 자동 설치. 여러 파일·디렉터리도 지원.
---

# show-glow — glow로 문서 보여주기

## 목적
대표님의 **"보여줘"는 항상 `glow` 렌더 방식**으로 처리한다. `cat`/`Read` 원문 덤프 대신,
터미널에서 마크다운을 서식 그대로(제목·표·코드블록·리스트) 렌더한다.

## 트리거
- "보여줘" / "보여 줘" / "보여줄래" (특정 파일·문서 대상)
- "/show <경로>"
- "glow로 보여줘" / "glow로 열어줘" / "이 문서 보여줘" / "이 파일 열어줘"
- 설계 문서·스펙·리포트·README·마크다운을 **확인**하려는 의도

## 실행 절차
1. **대상 경로 확정**: 대표님이 준 경로. 안 줬으면 직전 대화에서 만든/언급한 파일을 사용.
2. **glow 존재 확인 → 없으면 자동 설치** (묻지 않고 실행):
   ```bash
   command -v glow >/dev/null 2>&1 || brew install glow
   ```
   - brew 없으면: `go install github.com/charmbracelet/glow@latest` 또는 대표님께 설치 방법 1줄 안내.
3. **렌더** (폭 100 고정, 페이저 없이 스트리밍):
   ```bash
   glow -w 100 "<경로>"
   ```
   - 여러 파일: 각각 순차 렌더(파일명 헤더 1줄 출력 후).
   - 디렉터리: `glow "<디렉터리>"`로 목차 렌더(디렉터리는 -w 생략 가능).
4. 출력은 그대로 대표님께 전달. 요약·해설은 **요청 시에만** 덧붙인다(기본은 렌더만).

## 규칙
- **glow가 기본**이다. `cat`/`Read`로 원문 덤프하지 않는다(대표님이 "원문으로"라고 명시할 때만 예외).
- 경로에 **공백**이 있으면 반드시 따옴표로 감싼다 (예: `0017_SocialDoctors ` 처럼 후행 공백 프로젝트).
- glow 설치는 T0(침묵 자동). 묻지 않고 설치 후 진행.
- 마크다운이 아닌 파일(.ts/.json 등)도 glow가 코드블록으로 렌더 가능 — 그대로 `glow -w 100` 사용.

## 예시
```bash
# 단일 문서
glow -w 100 "docs/superpowers/specs/2026-07-10-hybrid-cli-fanout-publish-design.md"

# 여러 문서
for f in README.md CHANGELOG.md; do echo "── $f ──"; glow -w 100 "$f"; done

# 디렉터리 목차
glow "docs/superpowers/specs"
```
