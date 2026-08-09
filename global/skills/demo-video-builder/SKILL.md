---
name: demo-video-builder
description: Use when the user asks to make a demo/walkthrough/자체테스트 video of a web app or workflow (영상/데모영상/시연영상/동영상 만들어). Builds a narrated, subtitled, wide (16:9) MP4 from real browser captures using a scene-by-scene verify-then-assemble method that avoids black-screen playback.
---

# Demo Video Builder — 씬별 검증 후 조립

웹앱/워크플로우의 **데모·시연·자체테스트 영상**을 만든다. 대표님이 "영상 만들어 / 데모영상 / 시연영상"이라 하면 이 스킬을 따른다.

## 핵심 원칙 (실패에서 나온 규율)

1. **씬별 (정의 ↔ 실제 화면) 대조 검증 후 마지막에 조립.** 다 만들고 끝에 확인하지 말 것. 씬 하나를 캡처하면 그 자리에서 "자막이 주장하는 내용"과 "화면이 실제로 보여주는 내용"이 일치하는지 눈으로 본다. 불일치면 그 씬만 고쳐 재캡처. **통과한 씬만 최종 리스트에 넣는다.** (정본 대조 규율의 영상판)

2. **실제 브라우저에서 직접 캡처.** Mock/합성 아님. Playwright(또는 claude-in-chrome)로 로그인 → 데이터 준비 → 실행 완료 상태 → 카드/화면 클릭 → 캡처. 결과가 나온 완료 상태를 찍어야 프리뷰가 실증된다.

3. **프리뷰(결과)를 펼쳐서 찍는다.** 카드/패널만 선택된 정적 화면은 프리뷰가 빈약하다. **더블클릭 등으로 실제 결과(차트·그래프·표·텍스트)를 하단/결과 영역에 펼친 뒤** 캡처하면 자막이 주장하는 내용이 화면에 실재한다.

4. **와이드 16:9.** 쇼츠(세로)로 만들지 말 것. 원본 캡처(예: 1600×1000)를 1280×720에 레터박스 — 좌우 여백 최소, **세로 안 잘림.** 크롭으로 좌우를 자르면 "쇼츠처럼 잘렸다" 소리 나온다.

5. **인트로/아웃트로를 반드시 넣는다.** IDS 배열에 `intro`와 `outro`가 들어갔는지 **실물 프레임을 추출해 눈으로 확인**한다("들어갔겠지"로 넘기지 말 것 — 잘 빼먹는다). 인트로=로고 화면(부담 없는 은은한 배경 + 우하단 작게 `Created by <도메인>`). 아웃트로=마무리 멘트.

6. **keyframe 매초 강제 = 검은화면 근본해결.** 정적 이미지 시퀀스 영상은 I-frame이 1프레임에만 있으면 재생기가 검은화면을 낸다. `-g $FPS -keyint_min $FPS -sc_threshold 0`로 매초 keyframe을 강제한다. 빌드 후 `I-frame 수 ≈ 영상 초` 인지 확인.

7. **밝기 추출 통과 ≠ 재생 OK.** 반드시 실제 재생기로 열어(`open file.mp4`) 대표님 화면에서 눈으로 확인한다. 다지점 밝기(여러 초 지점 추출)도 함께 본다 — 로고/아웃트로 씬은 다크라 밝기 낮음이 정상.

8. **속도.** AI 테스트 속도는 매우 빠르지만, 영상은 **눈으로 따라 이해하는 속도**여야 한다. 씬 길이 = 나레이션 길이(TTS)에 맞춘다.

## 절차

### 0) 씬 대장 정의
각 씬 = `(캡처소스, 씬id, 자막)`. 자막이 곧 그 씬의 "정의"다. intro/s0(전체 조망)/s1~sN(단계)/outro.

### 1) 브라우저로 실제 캡처
```
- Playwright: browser_resize(1600,1000) → navigate → 로그인 → 데이터 업로드 → 전체실행(완료 폴링)
- "전체 보기" 버튼으로 전체 조망 1장 (설명 시작점)
- 각 단계 카드/화면 클릭 → 필요시 더블클릭으로 결과 펼침 → browser_take_screenshot(scale:device)
- 캡처를 scratchpad/panels/ 에 저장
```

### 2) 씬별 검증 (핵심)
각 캡처를 Read로 열어 눈으로 본다:
- 자막이 말하는 수치/개념이 화면에 실재하나?
- 없으면 → 결과를 펼쳐 재캡처 or 자막 수정 or 캡처 대상 카드 교체.
- PASS/보강/수정 판정을 대장에 기록. 통과만 최종 리스트로.

### 3) 나레이션 TTS
OpenAI tts-1, voice=nova. 씬마다 mp3. 자막을 고쳤으면 그 씬 나레이션도 재생성(자막↔음성 일치). 마무리 멘트 나레이션 필수.
```python
from openai import OpenAI
c = OpenAI(api_key=os.environ["OPENAI_API_KEY"])
r = c.audio.speech.create(model="tts-1", voice="nova", input=text)
r.stream_to_file(path)
```

### 4) 씬 이미지 생성 (자막 합성 + 레터박스 + 로고/아웃트로)
`scripts/make_scenes.py` 참고. 1600×1000 → 1280×720 레터박스, 하단 자막 박스, 인트로 로고(은은한 그라디언트+우하단 서명), 아웃트로 마무리 멘트.

### 5) 조립 (keyframe 강제, concat 없이 단일 인코딩)
`scripts/build_video.sh` 참고. IDS에 intro/outro 포함. 이미지 시퀀스+오디오를 한 번에 인코딩(경계 검은프레임 회피) + `-g $FPS -keyint_min $FPS -sc_threshold 0`.

### 6) 검증 + 재생
- I-frame 수 ≈ 영상 초 확인
- intro/outro 실물 프레임 추출해 눈으로 확인 (있는지)
- 다지점 밝기
- `open file.mp4`로 실제 재생 확인

## 참고 스크립트
- `scripts/make_scenes.py` — 씬 이미지 생성(레터박스+자막+로고/아웃트로). 캡처 경로/씬 대장/도메인만 바꿔 재사용.
- `scripts/build_video.sh` — keyframe 강제 단일 인코딩. IDS·나레이션 경로만 조정.

## 안티패턴 (하지 말 것)
- ❌ 크롭해서 좌우 자르기(쇼츠 됨)
- ❌ concat demuxer/filter로 씬 붙이기(경계 검은프레임)
- ❌ I-frame 1개짜리로 인코딩(재생기 검은화면)
- ❌ 밝기만 보고 "재생 OK" 단정
- ❌ intro/outro 넣었다고 가정하고 프레임 확인 안 하기
- ❌ 결과 안 펼치고 정적 패널만 찍기(프리뷰 빈약)
- ❌ 자막과 화면이 불일치한 채로 조립
