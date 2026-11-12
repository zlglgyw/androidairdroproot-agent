#!/usr/bin/env bash
# Kunci layar HP — satu tugas pegang layar, yang lain menunggu.
# Dibuat supaya beberapa tugas terjadwal (cron) dan tugas antrean tidak
# rebutan layar HP lagi.
#
# Cara pakai (dari worker/agen, sebelum menyentuh HP):
#   lock.sh acquire <owner> "<tugas>"   # owner: worker-a | worker-b | antrean | <nama-tugas>
#   lock.sh release <owner>
#   lock.sh status
#   lock.sh pause  "<alasan>"           # jeda darurat -> semua tugas berhenti
#   lock.sh resume
#
# Aturan:
# - Kunci berlaku 15 menit (900 detik). Pemegang yang sama boleh perpanjang
#   dengan acquire ulang. Kunci kedaluwarsa otomatis lepas sendiri, jadi
#   tugas yang mati di tengah jalan tidak memacetkan sistem selamanya.
# - Kalau kunci sedang dipegang tugas lain: acquire GAGAL (exit 1) dan tugas
#   TIDAK BOLEH menyentuh HP — diam, coba lagi putaran berikutnya. Ini yang
#   membuat aturan "tugas yang jalan duluan didahulukan" jadi otomatis.
# - Kalau file state/pause ada: semua acquire GAGAL (exit 2) — mode jeda.
# - Kunci ini file lokal di mesin agen (home, bukan /tmp). Bukan pengunci
#   Android; semua worker HARUS memanggil script ini dulu. Worker yang
#   tidak memanggilnya tetap bisa menabrak — itu batasannya.
set -uo pipefail

SYS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$SYS_DIR/state"
LOCK_DIR="$STATE_DIR/screen.lock.d"
PAUSE_FILE="$STATE_DIR/pause"
TTL=900  # 15 menit

mkdir -p "$STATE_DIR"

now() { date +%s; }

lock_info() {
  # cetak: owner | task | acquired | expires  (atau kosong kalau tidak ada kunci)
  [ -d "$LOCK_DIR" ] || return 1
  local owner task acquired expires
  owner=$(cat "$LOCK_DIR/owner" 2>/dev/null || echo "?")
  task=$(cat "$LOCK_DIR/task" 2>/dev/null || echo "?")
  acquired=$(cat "$LOCK_DIR/acquired" 2>/dev/null || echo 0)
  expires=$(cat "$LOCK_DIR/expires" 2>/dev/null || echo 0)
  echo "$owner | $task | acquired=$acquired | expires=$expires"
}

is_stale() {
  local expires
  expires=$(cat "$LOCK_DIR/expires" 2>/dev/null || echo 0)
  [ "$(now)" -ge "$expires" ]
}

cmd_status() {
  if [ -f "$PAUSE_FILE" ]; then
    echo "PAUSED: $(cat "$PAUSE_FILE" 2>/dev/null || echo "jeda aktif")"
  fi
  if [ -d "$LOCK_DIR" ]; then
    if is_stale; then
      echo "STALE: $(lock_info) (kedaluwarsa, akan dilepas saat acquire berikutnya)"
    else
      echo "HELD: $(lock_info)"
    fi
  else
    echo "FREE: tidak ada yang memegang layar"
  fi
}

cmd_acquire() {
  local owner="$1" task="${2:-}"
  if [ -f "$PAUSE_FILE" ]; then
    echo "PAUSED: jeda aktif — $(cat "$PAUSE_FILE" 2>/dev/null)" >&2
    return 2
  fi
  # Kunci kedaluwarsa: lepas dulu, lalu coba lagi.
  if [ -d "$LOCK_DIR" ] && is_stale; then
    rm -rf "$LOCK_DIR"
  fi
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "$owner" > "$LOCK_DIR/owner"
    echo "$task" > "$LOCK_DIR/task"
    echo "$(now)" > "$LOCK_DIR/acquired"
    echo "$(( $(now) + TTL ))" > "$LOCK_DIR/expires"
    echo "ACQUIRED: $owner — $task (berlaku 15 menit)"
    return 0
  fi
  # Sudah dipegang orang lain — cek apakah pemegangnya kita sendiri (perpanjang).
  local holder
  holder=$(cat "$LOCK_DIR/owner" 2>/dev/null || echo "?")
  if [ "$holder" = "$owner" ]; then
    echo "$(( $(now) + TTL ))" > "$LOCK_DIR/expires"
    echo "RENEWED: $owner — $task (diperpanjang 15 menit)"
    return 0
  fi
  echo "BUSY: layar sedang dipegang $(lock_info) — jangan sentuh HP, coba lagi putaran berikutnya" >&2
  return 1
}

cmd_release() {
  local owner="$1"
  [ -d "$LOCK_DIR" ] || { echo "FREE: tidak ada kunci untuk dilepas"; return 0; }
  local holder
  holder=$(cat "$LOCK_DIR/owner" 2>/dev/null || echo "?")
  if [ "$holder" != "$owner" ]; then
    echo "DENIED: kunci dipegang $holder, bukan $owner — tidak dilepas" >&2
    return 1
  fi
  rm -rf "$LOCK_DIR"
  echo "RELEASED: $owner melepas layar"
}

cmd_pause() {
  local reason="${1:-jeda manual}"
  echo "$reason — $(date '+%Y-%m-%d %H:%M WIB')" > "$PAUSE_FILE"
  echo "PAUSED: $reason"
}

cmd_resume() {
  rm -f "$PAUSE_FILE"
  echo "RESUMED: jeda dicabut, tugas boleh jalan lagi"
}

case "${1:-status}" in
  acquire) [ $# -ge 2 ] || { echo "pakai: lock.sh acquire <owner> \"<tugas>\"" >&2; exit 2; }; cmd_acquire "$2" "${3:-}" ;;
  release) [ $# -ge 2 ] || { echo "pakai: lock.sh release <owner>" >&2; exit 2; }; cmd_release "$2" ;;
  status)  cmd_status ;;
  pause)   cmd_pause "${2:-}" ;;
  resume)  cmd_resume ;;
  *) echo "pakai: lock.sh {acquire|release|status|pause|resume}" >&2; exit 2 ;;
esac
