#!/usr/bin/env bash

# 실패 hook은 진단만 하며, 자체 오류로 원래 실패를 악화시키지 않는다.
payload=$(cat 2>/dev/null) || payload=''
if command -v jq >/dev/null 2>&1; then
  text=$(printf '%s' "$payload" | jq -c . 2>/dev/null) || text=$payload
else
  text=$payload
fi

emit() {
  printf '[tool-recover] %s\n  → %s\n' "$1" "$2"
  exit 0
}

# 2026-08-09: edge-tts의 -10%가 플래그로 오인된 실제 실패에서 추가했다.
if printf '%s' "$text" | grep -Eqi 'expected one argument|argument .*: expected'; then
  emit "값이 '-'로 시작하면 다음 플래그로 오인된다" \
    '--옵션="값" 처럼 등호 형식을 쓰거나 -- 로 구분자를 넣어라'
fi

# 2026-08-09: 긴 목록 변수로 27개 중 0개가 복사된 실제 실패에서 추가했다.
if printf '%s' "$text" | grep -Eqi 'bad substitution|unbound variable|parameter not set'; then
  emit '변수 확장이 의도대로 되지 않았다' \
    '긴 목록은 변수 대신 파일로 만들어 while read -r 로 순회하라. set -u 환경이면 ${VAR:-} 기본값을 써라'
fi

if printf '%s' "$text" | grep -Fqi 'no matches found'; then
  emit 'zsh는 매칭 없는 glob에서 명령 자체를 실행하지 않는다(bash와 다름)' \
    '앞에 setopt NULL_GLOB 을 넣거나 경로를 따옴표로 감싸거나 ls ... 2>/dev/null || true 로 감싸라'
fi

if printf '%s' "$text" | grep -Fqi 'No such file or directory'; then
  emit '경로가 존재하지 않는다' \
    '상위 디렉터리부터 ls로 확인하라. ~ 확장이 따옴표 안에서 막혔을 수 있다("~/..." 는 확장되지 않는다)'
fi

if printf '%s' "$text" | grep -Eqi 'Permission denied|Operation not permitted'; then
  emit '실행 권한 또는 macOS 보호 영역 문제' \
    'chmod +x 를 확인하고, 화면기록/디스크접근이 필요한 명령이면 시스템 설정에서 권한을 부여해야 한다'
fi

# 2026-08-09: source 대상의 조기 종료로 함수 정의에 못 간 실제 실패도 이 계열이다.
if printf '%s' "$text" | grep -Fqi 'command not found'; then
  emit '해당 CLI가 설치돼 있지 않거나 PATH에 없다' \
    'which 로 확인하고 brew/pip 설치를 안내하라. 설치돼 있는데 안 잡히면 절대경로를 쓰라'
fi

if printf '%s' "$text" | grep -Eqi 'timed out|timeout'; then
  emit '실행이 제한 시간을 넘겼다' \
    '배치 크기를 줄이거나 run_in_background 로 돌려라. 45초 CDP 제한이 걸린 경우 루프 반복수를 줄여라'
fi

if printf '%s' "$text" | grep -Eqi '커밋 차단|pre-commit hook|rejected'; then
  emit 'hook 또는 원격이 커밋을 막았다' \
    'hook 출력을 먼저 읽어라. 우회하지 말고 원인을 고쳐라. 오탐이면 hook 규칙을 고치는 것이 맞다'
fi

if printf '%s' "$text" | grep -Eqi 'ModuleNotFoundError|No module named'; then
  emit '파이썬 패키지가 없다' \
    'pip3 install <모듈> 로 설치하라. 가상환경을 쓰는 스크립트면 그 환경에서 설치해야 한다'
fi

if printf '%s' "$text" | grep -Eqi 'JSONDecodeError|Expecting value'; then
  emit 'JSON이 깨졌거나 비어 있다' \
    '파일 크기를 먼저 확인하라(0바이트일 수 있다). 백업본이 있으면 대조하라'
fi

exit 0
