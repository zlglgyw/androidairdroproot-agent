#!/bin/bash
# Helper phone_server v3 (template).
# Konfigurasi dibaca dari file config.sh di samping script ini, atau dari
# environment: PHONE_BASE, PHONE_TOKEN, PHONE_PROXY (opsional).
# Salin config.example ke config.sh lalu isi nilai aslinya — JANGAN pernah
# menulis token/IP asli di script ini.
#
# Penggunaan:
#   ./ps.sh ping | health | shot <nama> | ui | screen | ocr
#   ./ps.sh tap <x> <y> | tap_text "<teks>" | tap_resource "<id>"
#   ./ps.sh swipe <x1> <y1> <x2> <y2> | scroll <up|down|left|right>
#   ./ps.sh long_press <x> <y> | double_tap <x> <y>
#   ./ps.sh type [--clear] [--enter] "<teks>"
#   ./ps.sh key <kode> | launch <paket> | stop_app <paket>
#   ./ps.sh record_start [detik] | record_stop | recording [nama]
#   ./ps.sh trace | logcat [n] | wait <detik>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/config.sh" ] && source "$SCRIPT_DIR/config.sh"

PHONE_BASE="${PHONE_BASE:-}"
PHONE_TOKEN="${PHONE_TOKEN:-}"
PHONE_PROXY="${PHONE_PROXY:-}"

if [ -z "$PHONE_BASE" ] || [ -z "$PHONE_TOKEN" ]; then
  echo "error: PHONE_BASE dan PHONE_TOKEN belum diisi." >&2
  echo "Salin config.example ke config.sh lalu isi, atau set environment:" >&2
  echo "  export PHONE_BASE=http://IP-TAILSCALE-HP:8765 PHONE_TOKEN=TOKEN-ANDA" >&2
  exit 2
fi

DIR="$SCRIPT_DIR/screenshots"
mkdir -p "$DIR"

CURL_OPTS=(-s)
[ -n "$PHONE_PROXY" ] && CURL_OPTS+=(--proxy "$PHONE_PROXY")

# api_get <path> [max-time]
api_get() {
  curl "${CURL_OPTS[@]}" --max-time "${2:-15}" -H "X-Token: $PHONE_TOKEN" "$PHONE_BASE$1"; echo
}

# api_post <path> <json-body> [max-time]
api_post() {
  curl "${CURL_OPTS[@]}" --max-time "${3:-15}" -X POST -H "X-Token: $PHONE_TOKEN" \
    -H 'Content-Type: application/json' -d "$2" "$PHONE_BASE$1"; echo
}

# json_escape <teks> — escape minimal untuk string JSON
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/ /g'
}

cmd="${1:-}"; shift || true
case "$cmd" in
  ping) api_get "/ping" ;;
  health) api_get "/health" ;;
  shot)
    [ -n "${1:-}" ] || { echo "penggunaan: ps.sh shot <nama-file>" >&2; exit 2; }
    curl "${CURL_OPTS[@]}" --max-time 30 -H "X-Token: $PHONE_TOKEN" \
      "$PHONE_BASE/screenshot" -o "$DIR/$1" && echo "saved $DIR/$1" ;;
  ui) api_get "/ui" 20 ;;
  screen) api_get "/screen" 30 ;;
  ocr) api_get "/ocr" 30 ;;
  tap) api_post "/tap" "{\"x\":$1,\"y\":$2}" ;;
  tap_text) api_post "/tap_text" "{\"text\":\"$(json_escape "$1")\"}" ;;
  tap_resource) api_post "/tap_resource" "{\"resource\":\"$(json_escape "$1")\"}" ;;
  swipe) api_post "/swipe" "{\"x1\":$1,\"y1\":$2,\"x2\":$3,\"y2\":$4}" ;;
  scroll) api_post "/scroll" "{\"direction\":\"$1\"}" ;;
  long_press) api_post "/long_press" "{\"x\":$1,\"y\":$2}" ;;
  double_tap) api_post "/double_tap" "{\"x\":$1,\"y\":$2}" ;;
  type)
    clear=false; enter=false
    while [ $# -gt 0 ]; do
      case "$1" in
        --clear) clear=true; shift ;;
        --enter) enter=true; shift ;;
        *) break ;;
      esac
    done
    api_post "/type" "{\"text\":\"$(json_escape "${1:-}")\",\"clear\":$clear,\"enter\":$enter}" ;;
  key) api_post "/key" "{\"key\":$1}" ;;
  launch) api_post "/launch" "{\"package\":\"$(json_escape "$1")\"}" ;;
  stop_app) api_post "/stop_app" "{\"package\":\"$(json_escape "$1")\"}" ;;
  record_start)
    n="${1:-30}"
    api_post "/record/start" "{\"time_limit\":$n}" ;;
  record_stop) api_post "/record/stop" "{}" ;;
  recording)
    name="${1:-recording.mp4}"
    curl "${CURL_OPTS[@]}" --max-time 300 -H "X-Token: $PHONE_TOKEN" \
      "$PHONE_BASE/recording" -o "$DIR/$name" && echo "saved $DIR/$name" ;;
  trace) api_get "/trace" ;;
  logcat) api_get "/logcat?n=${1:-200}" 20 ;;
  wait) sleep "$1"; echo "waited $1" ;;
  *)
    echo "unknown: $cmd" >&2
    echo "penggunaan: ps.sh ping|health|shot|ui|screen|ocr|tap|tap_text|tap_resource|swipe|scroll|long_press|double_tap|type|key|launch|stop_app|record_start|record_stop|recording|trace|logcat|wait" >&2
    exit 1 ;;
esac
