# Sistem Airdrop HP — Sisi Agen

Repo ini berisi sisi agen dari sistem airdrop HP dua sisi: skrip dan
panduan untuk agen (manusia atau AI) yang mengendalikan HP Android dari
jarak jauh. Sisi HP-nya (server yang berjalan di Termux) ada di repo
`androidairdroproot`.

Repo ini adalah **sistem mentah kosong + panduan**: semua skrip, aturan,
dan template lengkap, tanpa data pribadi dan tanpa riwayat airdrop.
Siapa pun yang clone mendapatkan kerangka sistem yang siap diisi dengan
datanya sendiri.

## Arsitektur dua sisi

```
Channel Telegram publik (t.me/s)
        │  monitor.sh (polling berkala)
        ▼
   Agen (mesin ini) ── ps.sh ── Tailscale ── phone_server (Termux di HP)
        │                                   └─ layar HP: tap, ketik,
        │                                      swipe, OCR, rekam layar
        ├── lock.sh   (satu kunci layar)
        ├── QUEUE.md  (daftar tunggu tugas)
        └── DEDUP.md  (registri anti-dobel)
```

- **Sisi HP** (`androidairdroproot`): `phone_server.py` v3 berjalan di
  Termux, menerima perintah HTTP dan menggerakkan layar.
- **Sisi agen** (repo ini): `ps.sh` memanggil server, `monitor.sh`
  mengawasi channel, `lock.sh` + `QUEUE.md` mengatur giliran layar,
  `DEDUP.md` mencegah tugas ganda.

## Setup

### 1. Siapkan sisi HP dulu

Ikuti README di repo `androidairdroproot`: install server di Termux,
isi `phone_config.json`, jalankan server, pastikan bisa di-ping dari
mesin ini.

### 2. Konfigurasi agen

```sh
git clone https://github.com/zlglgyw/androidairdroproot-agent.git
cd androidairdroproot-agent

# Konfigurasi koneksi ke HP:
cp config.example config.sh
# Edit config.sh: isi PHONE_BASE (IP Tailscale HP + port) dan PHONE_TOKEN
# (token yang sama dengan phone_config.json di HP).

# Daftar channel yang dipantau monitor:
cp channels.txt.example channels.txt
# Edit channels.txt: satu nama channel per baris, tanpa @.
```

Tes koneksi:

```sh
./ps.sh ping
./ps.sh health
./ps.sh shot test.png   # screenshot tersimpan di screenshots/
```

### 3. Jalankan monitor

`monitor.sh` dirancang untuk dipanggil berkala (mis. tiap 60 detik) oleh
scheduler/hook di runtime agen. Script ini:

- Membaca daftar channel dari `channels.txt` (berhenti dengan pesan
  error kalau file tidak ada atau kosong — isi dulu).
- Mengambil halaman publik tiap channel, mem-parsing post baru.
- Membangunkan agen (fungsi `wake`) hanya kalau ada post airdrop baru;
  kalau tidak ada, diam (`silent`).
- Menyimpan state di `state/` (ID terakhir per channel, hash konten
  yang sudah dilihat). State ini TIDAK masuk repo.

Jalan pertama untuk sebuah channel hanya mencatat baseline (ID terakhir)
tanpa membangunkan — supaya post lama tidak membanjiri.

Prompt worker yang dipakai saat monitor membangunkan agen ada di
`hooks/telegram-monitor-prompt.md` (aturan klasifikasi post:
CANDIDATE / SKIP / DUPLICATE).

## Cara kerja

### Monitor — `monitor.sh`

Polling channel Telegram publik, anti-dobel 2 lapis:

1. **ID post** per channel (hanya proses ID yang lebih besar dari
   terakhir).
2. **Hash isi** (sha256 teks post yang dinormalisasi, 100 terakhir) —
   teks yang sama persis, walau di channel lain atau repost, hanya
   diproses sekali.

Lapis ke-3 adalah registri proyek (`DEDUP.md`), dicek agen sebelum
eksekusi — karena proyek yang sama bisa diposting dengan teks berbeda.

Parser mengambil HANYA div `tgme_widget_message_text js-message_text`
(teks post itu sendiri). Div `js-message_reply_text` adalah kutipan
reply dan HARUS diabaikan.

### Antrean — `QUEUE.md`

Semua tugas airdrop masuk antrean dulu, dikerjakan SATU PER SATU,
maksimal 15 menit per tugas. Prioritas: (1) whitelist/waitlist gratis
slot terbatas, (2) misi XP/poin gratis, (3) lainnya. Free mint masuk
antrean dan dikerjakan (dengan gerbang di bawah). Yang berbayar tidak
pernah masuk antrean otomatis.

Aturan 1x coba + lapor gagal: airdrop baru hanya dicoba 1x — kalau
gagal, laporkan alasannya di laporan proyeknya dan lanjut ke tugas
berikutnya.

### Kunci layar — `lock.sh`

HP cuma punya satu layar. Semua tugas yang mau menyentuh HP WAJIB pegang
kunci dulu:

```sh
./lock.sh acquire worker-a "nama tugas" || exit 0   # layar dipakai tugas lain — diam
# ... kerja ...
./lock.sh release worker-a
```

Kunci berlaku 15 menit lalu lepas sendiri. `lock.sh pause "<alasan>"`
menghentikan semua tugas sampai `lock.sh resume`. Aturan tabrakan:
tugas yang sudah jalan lebih dulu didahulukan.

### Registri — `DEDUP.md`

Sebelum mengerjakan post baru, cocokkan kunci proyek (alamat kontrak,
domain/link resmi, atau nama proyek yang dinormalisasi) ke registri.
Kalau sudah ada dengan status apa pun — JANGAN kerjakan lagi. Setiap
proyek yang dikerjakan/dilewati WAJIB masuk registri dengan status +
tanggal + alasan.

### Helper HP — `ps.sh`

Pembungkus `curl` ke phone_server. Lihat `./ps.sh` tanpa argumen untuk
daftar perintah. Mencakup semua endpoint v3: `ping`, `health`, `shot`,
`ui`, `screen`, `ocr`, `tap`, `tap_text`, `tap_resource`, `swipe`,
`scroll`, `long_press`, `double_tap`, `type` (dengan `--clear`/`--enter`),
`key`, `launch`, `stop_app`, `record_start`, `record_stop`, `recording`,
`trace`, `logcat`, `wait`.

## Aturan main

Ringkasan — selengkapnya di `SYSTEM.md`:

- Hanya yang GRATIS. Berbayar = konfirmasi dulu.
- Free mint dikerjakan. Gerbang: kontrak mint-only, gas saja dan
  gas < $0,10. Kalau butuh wallet agen eksternal, beri tahu pengguna
  dulu — jangan kerjakan langsung.
- Jangan menebak data. Kalau butuh data lain / connect wallet / sign,
  tanya pengguna dulu.
- Seed phrase wallet baru dicatat pengguna sendiri; agen tidak pernah
  menyimpan seed phrase. Jangan pernah minta/bagikan seed phrase.
- Semua airdrop dikerjakan di HP lewat `phone_server` — tidak ada kerja
  lewat browser cloud.
- Kalau suatu airdrop punya daily check-in / daily claim, OTOMATIS
  buatkan jadwal untuk klaim/check-in-nya.
- Laporan per proyek hanya ke laporan proyek itu; jangan campur dengan
  laporan sistem.

## Membuat jadwal (cron)

Repo ini TIDAK berisi definisi jadwal (cron) — jadwal terikat pada
runtime/scheduler yang dipakai masing-masing pengguna, dan berisi
data pengguna. Buat jadwal sendiri dengan pola ini:

- **Loop tugas berulang** (mis. klaim berkala): interval sesuai
  kebutuhan, isi perintahnya: acquire kunci (`lock.sh acquire
  <owner> "<tugas>"`), kerjakan lewat `ps.sh`, release kunci, laporkan
  hasil ke laporan proyeknya.
- **Run antrean**: jadwal sekali jalan (runonce) atau berkala yang
  membaca `QUEUE.md`, mengambil tugas MENUNGGU paling atas, dan
  mengerjakannya satu per satu dengan kunci `antrean`.
- **Sync/claim harian**: satu jadwal per proyek yang punya daily
  check-in/claim, sesuai aturan cron daily otomatis di atas.
- **Penjaga phone_server**: jadwal ping berkala (`./ps.sh ping`)
  supaya server tidak mati karena idle timeout — atau biarkan server
  mati sendiri kalau memang sedang tidak dipakai.

Setiap jadwal yang menyentuh HP WAJIB memakai `lock.sh` (lihat
`ANTREAN-DAN-KUNCI.md` untuk cuplikan yang ditempel ke definisi
jadwal).

## Skill & prompt

- `skills/SKILL-AIRDROP.md` — skill mengerjakan task airdrop, posting
  di X, dan connect wallet (dengan aturan keamanan).
- `skills/PROMPT-HERMES-ROOT.md` — prompt agen pengendali HP root
  (Android): kemampuan, aturan, dan batasan.
- `hooks/telegram-monitor-prompt.md` — prompt worker klasifikasi post
  dari monitor.

Semua file di atas adalah template: isi placeholder dari konfigurasi
pengguna sebelum dipakai.

## Keamanan

- **Jangan pernah commit file konfigurasi asli.** `config.sh`,
  `channels.txt`, dan `state/` sudah masuk `.gitignore`.
- **Token dan IP tidak pernah masuk repo.** Semua nilai rahasia tinggal
  di file konfigurasi lokal (`config.sh` di sini,
  `phone_config.json` di HP).
- **Server HP tanpa shell bebas.** phone_server hanya mengizinkan
  perintah allowlist — tidak ada endpoint yang menjalankan shell
  sembarangan. Blok kata berisiko dan deteksi captcha aktif di server.
- **Seed phrase bukan urusan repo.** Agen tidak pernah menyimpan seed
  phrase di file mana pun — pengguna mencatatnya sendiri.

## Isi repo

| File | Keterangan |
| --- | --- |
| `ps.sh` | Helper pemanggil phone_server (template). |
| `lock.sh` | Kunci layar (satu tugas satu waktu). |
| `monitor.sh` | Monitor channel Telegram. |
| `channels.txt.example` | Template daftar channel. |
| `config.example` | Template konfigurasi koneksi. |
| `SYSTEM.md` | Desain sistem + aturan. |
| `QUEUE.md` | Template antrean tugas. |
| `DEDUP.md` | Template registri anti-dobel. |
| `ANTREAN-DAN-KUNCI.md` | Desain antrean & kunci layar. |
| `skills/` | Skill airdrop + prompt pengendali HP root. |
| `hooks/` | Prompt worker monitor. |
