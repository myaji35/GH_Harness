# skill-patches — 외부 스킬에 우리가 얹은 변경분

`global/skills/`와 다르다. 여기는 **우리가 만들지 않은 스킬**에 우리가 추가·수정한 파일만 보관한다.

## 왜 분리하는가

`media-use`, `hyperframes`, `gstack` 같은 스킬은 외부에서 배포된다. 전체를 이 저장소에 복사하면
① 남의 코드를 우리 이력으로 떠안고 ② 상류 업데이트를 받을 때마다 충돌한다.
그래서 **우리 변경분만** 여기에 두고, 상류 업데이트 후 다시 얹는 방식을 쓴다.

## 현재 보관 중

### `media-use/` — TTS 백엔드 2종 (ISS-410, 2026-08-09)

`~/.claude/skills/media-use/`에 얹은 변경분.

| 파일 | 성격 |
|---|---|
| `scripts/lib/tts-edge-provider.mjs` | **신규** — MS TTS (Edge). 키 불필요, 한국어 3종 |
| `scripts/lib/tts-edge-provider.test.mjs` | **신규** — 테스트 3건 |
| `scripts/lib/tts-vibevoice-provider.mjs` | **신규** — VibeVoice 골격. `VIBEVOICE_HOME` 설정 시에만 동작 |
| `scripts/lib/tts-vibevoice-provider.test.mjs` | **신규** — 테스트 3건 |
| `scripts/lib/registry.mjs` | **수정** — voice 체인에 2종 등록 |
| `scripts/lib/registry.test.mjs` | **수정** — sanctioned 화이트리스트에 2종 추가 |
| `audio/references/tts.md` | **수정** — 라우트 표에 MS TTS 행 + 설명 블록 |

voice 폴백 체인:

```
heygen.tts(P·유료) → kokoro.local(A) → edge.tts(N·무료) → vibevoice.local(A)
```

**주의** — `tts-vibevoice-provider.mjs`는 Microsoft가 딥페이크 우려로 내린 VibeVoice의
커뮤니티 사본을 전제로 한다. 라이선스 검증 전에는 고객 대상 상업 서비스에 쓰지 않는다.
사내 제작 한정, 생성 오디오에 AI 고지 필요. 파일 상단 주석에도 같은 내용이 있다.

## 상류 업데이트 후 복원 절차

```bash
# 1. media-use가 갱신되면 신규 파일 4개를 다시 넣는다
cp global/skill-patches/media-use/scripts/lib/tts-*.mjs \
   ~/.claude/skills/media-use/scripts/lib/

# 2. 수정 파일 3개는 diff를 보고 수동 병합한다 (상류가 같은 파일을 고쳤을 수 있음)
diff global/skill-patches/media-use/scripts/lib/registry.mjs \
     ~/.claude/skills/media-use/scripts/lib/registry.mjs

# 3. 검증
cd ~/.claude/skills/media-use
node --test scripts/lib/registry.test.mjs
node --test scripts/lib/tts-edge-provider.test.mjs scripts/lib/tts-vibevoice-provider.test.mjs
```

수정 파일 3개는 **덮어쓰지 말 것**. 상류 변경을 지울 수 있다.
