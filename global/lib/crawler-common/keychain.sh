#!/usr/bin/env bash
# crawler-common/keychain.sh — macOS Keychain wrapper (자격증명 저장/조회/삭제)
#
# 사용법:
#   source keychain.sh
#   kc_set datago id "myaccount"
#   kc_set datago pw "mypassword"
#   kc_get datago id
#   kc_del datago id
#
# 저장 형식: service="ghharness.<service>", account="<key>"
# 예: ghharness.datago / id, ghharness.datago / pw, ghharness.datago / cookie

set -euo pipefail

KC_PREFIX="${KC_PREFIX:-ghharness}"

_kc_service() { echo "${KC_PREFIX}.$1"; }

kc_set() {
  local service="$1" key="$2" value="$3"
  security delete-generic-password -s "$(_kc_service "$service")" -a "$key" >/dev/null 2>&1 || true
  security add-generic-password -s "$(_kc_service "$service")" -a "$key" -w "$value" -U
}

kc_get() {
  local service="$1" key="$2"
  security find-generic-password -s "$(_kc_service "$service")" -a "$key" -w 2>/dev/null
}

kc_has() {
  local service="$1" key="$2"
  security find-generic-password -s "$(_kc_service "$service")" -a "$key" -w >/dev/null 2>&1
}

kc_del() {
  local service="$1" key="$2"
  security delete-generic-password -s "$(_kc_service "$service")" -a "$key" >/dev/null 2>&1 || true
}

# 직접 실행 시 디버그 모드
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    set) kc_set "$2" "$3" "$4" ;;
    get) kc_get "$2" "$3" ;;
    has) kc_has "$2" "$3" && echo "yes" || echo "no" ;;
    del) kc_del "$2" "$3" ;;
    *)
      cat <<EOF
Usage:
  keychain.sh set <service> <key> <value>
  keychain.sh get <service> <key>
  keychain.sh has <service> <key>
  keychain.sh del <service> <key>
EOF
      ;;
  esac
fi
