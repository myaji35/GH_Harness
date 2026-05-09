---
name: datago-fetch
description: 공공데이터포털(data.go.kr) 자동 로그인·인증키 수집·데이터셋 검색·활용신청 큐. 자격증명은 macOS Keychain, 세션은 Playwright storageState로 재사용. 트리거: "공공데이터", "datago", "data.go.kr", "공공데이터 키 가져와", "/datago".
---

# datago-fetch — 공공데이터포털 자동화 스킬

## 역할
공공데이터포털 작업을 사람의 반복 입력 없이 처리. **로그인은 최초 1회만 사람이**, 이후는 모두 Claude가 CLI로 자동 호출.

## 핵심 원칙
- 자격증명은 macOS Keychain (`ghharness.datago` / `id`, `pw`)
- 세션은 `~/.config/gh-harness/datago-state.json` (Playwright storageState)
- 만료 감지 시 → 사용자에게 `datago login` 1회 재실행 요청
- 약관 동의가 필요한 활용신청은 **자동 클릭하지 않고 큐에만 등록**

## 트리거 → CLI 매핑

| 사용자 발화 | 실행 명령 |
|---|---|
| "공공데이터 로그인", "datago 설정" | `datago login` (헤디드 — 사람이 직접 클릭, 최초 1회) |
| "세션 갱신", "쿠키 만료" | `datago refresh` (자동 — L1 ID/PW + L2 Vision OCR) |
| "공공데이터 키 동기화", "API 키 가져와" | `datago sync-keys` (만료 시 refresh 자동) |
| "공공데이터에서 X 검색", "data.go.kr X 찾아" | `datago search "X"` |
| "X 데이터셋 신청해줘" | `datago apply <id>` (큐 등록 + URL 안내) |
| "공공데이터 키 목록", "내 API 키 뭐 있어?" | `datago list` |
| "X API 키 알려줘" / 코드에서 키 필요 | `datago key <name>` |
| "공공데이터 로그아웃" | `datago logout` |

## 표준 진행 흐름 (B안: L1+L2 자동 폴백)

```
1. 첫 사용 → datago whoami 로 로그인 여부 확인
2. 미로그인 → 사용자에게 1회 안내:
     "공공데이터포털 ID/PW를 한 번만 입력하면 이후 자동화됩니다.
      터미널에서 'datago login' 실행해주세요."
3. 로그인 완료 후 → datago sync-keys 자동 실행
4. 필요한 키는 datago key <name> 으로 stdout 받아 환경변수/스크립트에 주입

세션 만료 자동 폴백 (사용자 개입 거의 없음):
  sync-keys 실행 → exit 3 (만료) 감지
    ↓
  L1: datago refresh — Keychain의 ID/PW로 headless 자동 로그인
    ├─ ✅ 성공 → sync-keys 자동 재시도 → 완료 (사용자 모름)
    ├─ 이미지 CAPTCHA 감지 → L2로 폴백
    └─ reCAPTCHA/SSO 감지 → L3로 폴백
    ↓
  L2: Vision OCR — Anthropic Claude Vision으로 CAPTCHA 자동 풀이 (3회 재시도)
    ├─ ✅ 성공 → sync-keys 재시도
    └─ ❌ 실패 → L3
    ↓
  L3: 사용자에게 안내
       "reCAPTCHA/SSO 감지. 'datago login' 1회만 실행해주세요 (1분)"
```

## L2 Vision OCR 사전 조건
- `ANTHROPIC_API_KEY` 환경변수 또는 Keychain `ghharness.anthropic / api_key`
- 기본 모델: `claude-haiku-4-5-20251001` (빠르고 저렴, $0.001/회)
- 변경: `CAPTCHA_MODEL=claude-sonnet-4-6 datago refresh`

## cron 자동 갱신 (선택)
```cron
# 매일 9시 자동 키 동기화 (만료되면 자동 갱신, 실패 시 로그만 남김)
0 9 * * * ~/.local/bin/datago sync-keys >> ~/.config/gh-harness/datago.log 2>&1
```

## 키 사용 예시 (Claude가 코드에 주입할 때)

```bash
# 환경변수로
export PUBLIC_DATA_KEY=$(datago key apt-trade)
curl "https://api.odcloud.kr/...&serviceKey=$PUBLIC_DATA_KEY"

# Python에서
import subprocess
key = subprocess.check_output(["datago", "key", "apt-trade"]).decode().strip()
```

## 절대 하지 말 것
- ID/PW를 코드/로그/git에 평문 저장 금지 (Keychain만 사용)
- 활용신청 자동 클릭 (약관 동의 함의 위험)
- CAPTCHA/SSO 자동 우회 시도 (사이트 약관 위반)

## 산출 파일 위치
- `~/.config/gh-harness/datago-state.json` (Playwright 쿠키)
- `~/.config/gh-harness/datago-keys.json` (수집된 인증키)
- `~/.config/gh-harness/datago-pending.json` (승인 대기 큐)
- `~/.config/gh-harness/datago.log` (로그)

## 확장 위치
새로운 데이터 포털(서울열린데이터, 홈택스, KRX 등)은 같은 패턴으로 `global/skills/<portal>-fetch/` 추가. 공통 로직은 `global/lib/crawler-common/` 재사용.
