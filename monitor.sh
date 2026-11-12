#!/usr/bin/env bash
set -euo pipefail

# Monitor Sistem Airdrop HP — polling channel Telegram publik tiap 60 detik,
# bangunkan agen HANYA kalau ada post airdrop BARU. Bukan live stream.
# Daftar channel dibaca dari channels.txt di samping script ini (satu nama
# channel per baris, tanpa @). Kalau channels.txt tidak ada atau kosong,
# script berhenti dengan pesan error — isi dulu sebelum menjalankan.
# Eksekutor: agen lewat phone_server.
#
# Anti-dobel, 2 lapis:
#  1. ID: simpan ID post terakhir per channel, hanya proses ID > terakhir.
#  2. ISI: hash sha256 teks post (dinormalisasi). Hash yang sama — walau ID
#     baru atau di channel lain (repost admin) — dianggap dobel, tidak wake.
#     Simpan 100 hash terakhir.
# Lapis ke-3 (registri proyek di DEDUP.md) dicek AGEN sebelum eksekusi, karena
# proyek yang sama bisa diposting dengan teks berbeda (hash tidak sama).
#
# Aturan gagal: fetch gagal (403/429/timeout) -> log, lewati, JANGAN update
# state ke ID yang belum dibaca, supaya post itu tetap dicek di poll berikut.
# Jangan wake palsu. Dry-run: HATCH_HOOK_DRY_RUN=1 pakai salinan state.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SYS_DIR="$SCRIPT_DIR"
STATE_DIR="$SYS_DIR/state"
STATE_FILE="$STATE_DIR/last-ids.json"
SEEN_FILE="$STATE_DIR/seen.json"
mkdir -p "$STATE_DIR"
[ -f "$STATE_FILE" ] || echo '{}' > "$STATE_FILE"
[ -f "$SEEN_FILE" ] || echo '[]' > "$SEEN_FILE"

# Runtime hook (log/wake/silent) kalau tersedia; kalau tidak, fallback lokal
# supaya script tetap bisa dites manual dari terminal.
if [ -n "${HATCH_HOOK_RUNTIME:-}" ] && [ -f "$HATCH_HOOK_RUNTIME" ]; then
  source "$HATCH_HOOK_RUNTIME"
else
  log() { echo "[$(date '+%H:%M:%S')] $1 $2" >&2; }
  wake() { echo "WAKE: $1 $2" >> "$STATE_DIR/wake-queue.jsonl"; echo "WAKE: $1 $2"; }
  silent() { echo "SILENT: $1"; }
fi

if [ "${HATCH_HOOK_DRY_RUN:-0}" = "1" ]; then
  tmp_state="$(mktemp)"
  tmp_seen="$(mktemp)"
  cp "$STATE_FILE" "$tmp_state"
  cp "$SEEN_FILE" "$tmp_seen"
  STATE_FILE="$tmp_state"
  SEEN_FILE="$tmp_seen"
fi

CHANNELS_FILE="$SCRIPT_DIR/channels.txt"
if [ ! -f "$CHANNELS_FILE" ]; then
  echo "error: channels.txt tidak ditemukan di $SCRIPT_DIR." >&2
  echo "Salin channels.txt.example ke channels.txt lalu isi daftar channel (satu per baris)." >&2
  exit 2
fi
CHANNELS="$(grep -vE '^\s*(#|$)' "$CHANNELS_FILE" | tr -d '\r' | tr '\n' ' ')"
if [ -z "$CHANNELS" ]; then
  echo "error: channels.txt kosong — isi dulu daftar channel (satu nama channel per baris, tanpa @)." >&2
  exit 2
fi
UA1='Mozilla/5.0'
UA2='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36'

new_found=""

update_last_id() {
  local ch="$1" id="$2" tmp
  tmp="$(mktemp)"
  if jq --arg c "$ch" --argjson id "$id" '.[$c] = $id' "$STATE_FILE" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$STATE_FILE"
  else
    log "state update failed $ch" "{\"post_id\":$id}"
    rm -f "$tmp"
  fi
}

# --- Fetch semua channel secara paralel, masing-masing max 2 percobaan ---
FETCH_DIR="$(mktemp -d)"
for ch in $CHANNELS; do
  (
    if curl --fail --silent --show-error --max-time 20 \
        -A "$UA1" \
        "https://t.me/s/$ch" -o "$FETCH_DIR/$ch.html" 2>"$FETCH_DIR/$ch.err"; then
      echo 0 > "$FETCH_DIR/$ch.status"
    elif curl --fail --silent --show-error --max-time 20 \
        -A "$UA2" -H 'Accept-Language: en-US,en;q=0.9' \
        "https://t.me/s/$ch" -o "$FETCH_DIR/$ch.html" 2>"$FETCH_DIR/$ch.err"; then
      echo 0 > "$FETCH_DIR/$ch.status"
    else
      echo 1 > "$FETCH_DIR/$ch.status"
    fi
  ) &
done
wait || true

for ch in $CHANNELS; do
  posts_file="$(mktemp)"

  if [ ! -f "$FETCH_DIR/$ch.status" ] || [ "$(cat "$FETCH_DIR/$ch.status" 2>/dev/null)" != "0" ]; then
    log "fetch failed $ch after retry" "{\"error\":\"$(head -c 200 "$FETCH_DIR/$ch.err" 2>/dev/null | tr '"' "'")\"}"
    rm -f "$posts_file"
    continue
  fi
  html_file="$FETCH_DIR/$ch.html"

  # Parse SEMUA post: satu baris per post "id<TAB>teks".
  # Ambil HANYA div tgme_widget_message_text js-message_text (teks post itu
  # sendiri). Div js-message_reply_text adalah kutipan reply — HARUS diabaikan
  # (pelajaran: parser lama ambil div pertama sehingga post reply terbaca
  # sebagai teks post yang dikutip, hash sama, lalu dibuang anti-dobel).
  if ! python3 - "$html_file" "$ch" > "$posts_file" <<'PYEOF'
import re, html, sys
path, ch = sys.argv[1], sys.argv[2]
data = open(path, encoding="utf-8", errors="ignore").read()
parts = re.split(r'data-post="([^"]+)"', data)
seen_ids = set()
for i in range(1, len(parts) - 1, 2):
    pid = parts[i]
    if not pid.startswith(ch + "/"):
        continue
    try:
        num = int(pid.rsplit("/", 1)[1])
    except ValueError:
        continue
    if num in seen_ids:
        continue
    seen_ids.add(num)
    chunk = parts[i + 1]
    m = re.search(r'<div class="tgme_widget_message_text js-message_text"[^>]*>(.*?)</div>', chunk, re.S)
    txt = ""
    if m:
        txt = html.unescape(re.sub(r"<[^>]*>", " ", m.group(1)))
        txt = " ".join(txt.split())[:500]
    print(f"{num}\t{txt}")
PYEOF
  then
    log "parse failed $ch" '{}'
    rm -f "$posts_file"
    continue
  fi

  if [ ! -s "$posts_file" ]; then
    log "no posts parsed $ch" '{}'
    rm -f "$posts_file"
    continue
  fi

  # Mode baseline: jalan pertama untuk channel ini (belum ada last_id) —
  # catat ID terbesar sebagai titik awal, JANGAN wake (supaya post lama
  # tidak membanjiri). Wake hanya untuk post yang muncul SETELAH baseline.
  has_last=$(jq -r --arg c "$ch" 'has($c)' "$STATE_FILE" 2>/dev/null || echo false)
  max_id=$(sort -n -t"$(printf '\t')" -k1,1 "$posts_file" | tail -1 | cut -f1)
  if [ "$has_last" != "true" ]; then
    update_last_id "$ch" "$max_id"
    log "baseline $ch" "{\"last_id\":$max_id}"
    rm -f "$posts_file"
    continue
  fi

  last_id=$(jq -r --arg c "$ch" '.[$c] // 0' "$STATE_FILE" 2>/dev/null || echo 0)

  sort -n -t"$(printf '\t')" -k1,1 "$posts_file" -o "$posts_file" 2>/dev/null || true
  while IFS="$(printf '\t')" read -r pid text || [ -n "$pid" ]; do
    [ -n "$pid" ] || continue
    if [ "$pid" -le "$last_id" ]; then
      continue
    fi

    # Post ini sudah dibaca sekarang — update ID dulu, supaya tidak
    # ke-trigger dua kali walau langkah berikutnya gagal / dobel.
    update_last_id "$ch" "$pid"
    last_id="$pid"

    # Post tanpa teks (mis. foto saja): tidak bisa dicek, lewati.
    if [ -z "${text// }" ]; then
      continue
    fi

    # Anti-dobel isi: hash dari teks yang dinormalisasi.
    norm=$(printf '%s' "$text" | tr 'A-Z' 'a-z' | tr -s ' \t\n\r' ' ' | sed -e 's/^ *//' -e 's/ *$//')
    content_hash=$(printf '%s' "$norm" | sha256sum | cut -d' ' -f1)

    if jq -e --arg h "$content_hash" 'index($h) != null' "$SEEN_FILE" >/dev/null 2>&1; then
      log "duplicate content $ch" "{\"post_id\":$pid,\"hash\":\"${content_hash:0:12}\"}"
      continue
    fi

    tmp2="$(mktemp)"
    if jq --arg h "$content_hash" '. + [$h] | .[-100:]' "$SEEN_FILE" > "$tmp2" 2>/dev/null; then
      mv "$tmp2" "$SEEN_FILE"
    else
      rm -f "$tmp2"
    fi

    # Kata kunci airdrop (lebih luas dari hook mint lama): mint, claim,
    # airdrop, whitelist, waitlist, testnet, faucet. Kalau bukan airdrop,
    # diam saja. Agen yang menilai tiap post yang lolos.
    echo "$text" | grep -qiE 'mint|claim|airdrop|whitelist|waitlist|testnet|faucet' || continue

    log "new airdrop post $ch" "{\"post_id\":$pid,\"hash\":\"${content_hash:0:12}\",\"text\":\"$(echo "$text" | head -c 200 | tr '"' "'")\"}"
    new_found="$new_found $ch/$pid"
  done < "$posts_file"
  rm -f "$posts_file"
done
rm -rf "$FETCH_DIR"

if [ -n "$new_found" ]; then
  wake "new airdrop post in Telegram channels" "{\"posts\":\"$new_found\",\"channels\":\"$CHANNELS\"}"
else
  silent "no new airdrop posts"
fi
