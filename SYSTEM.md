# Sistem Airdrop HP — desain

Sistem untuk mengerjakan tugas airdrop dari channel Telegram publik,
dikerjakan di HP Android lewat `phone_server` (repo `androidairdroproot`).
Eksekutornya adalah agen (manusia atau AI) yang mengendalikan layar HP
dari jarak jauh.

## Cara kerja

1. `monitor.sh` mem-polling channel Telegram publik yang tercantum di
   `channels.txt` (lewat halaman publik `t.me/s/<channel>`) secara berkala.
   Parser mengambil HANYA `tgme_widget_message_text js-message_text` —
   teks post itu sendiri, bukan kutipan reply.
2. Kalau ada post airdrop BARU, monitor membangunkan agen. Agen membaca
   post itu, memverifikasi, dan mengerjakan tugasnya di HP lewat
   `phone_server`.
3. Hasil tiap proyek dilaporkan per proyek (satu laporan satu proyek);
   ringkasan berkala dikumpulkan terpisah.

## Aturan (berlaku penuh)

- Hanya yang GRATIS. Kalau berbayar, konfirmasi dulu ke pengguna.
- Free mint DIKERJAKAN. Gerbang: kontrak harus mint-only (tanpa
  swap/kirim/drain), gas saja dan gas < $0,10; free mint / winning claim
  dieksekusi langsung tanpa konfirmasi. PENGECUALIAN: kalau mint-nya butuh
  wallet agen eksternal (agentic wallet), JANGAN langsung kerjakan —
  beri tahu pengguna dulu.
- Slot terbatas diprioritaskan (whitelist/waitlist gratis dengan slot
  terbatas dulu), kerjakan langsung begitu lolos gerbang.
- Whitelist/waitlist gratis: daftar langsung tanpa konfirmasi. Berbayar:
  konfirmasi dulu.
- Jangan menebak data. Kalau butuh data lain / connect wallet / sign,
  tanya pengguna dulu.
- Data pendaftaran (X, email, Discord) diisi dari konfigurasi pengguna —
  tidak pernah ditebak dan tidak pernah ditulis di repo ini.
- Wallet: mint/claim dari HP memakai wallet HP yang pengguna tunjuk,
  dan tiap connect/sign tetap seizin pengguna dulu.
- Wallet baru: kalau suatu tugas butuh wallet yang belum ada (mis. untuk
  chain lain), install sendiri aplikasinya di HP dan buat sendiri
  wallet-nya — tidak perlu tanya pengguna dulu. Seed phrase wallet baru
  WAJIB dicatat pengguna sendiri; agen tidak pernah menyimpan seed phrase.
  Jangan pernah minta/bagikan seed phrase.
- SEMUA airdrop dikerjakan di HP — INI ATURAN. Tidak ada kerja airdrop
  lewat browser cloud; semua lewat `phone_server` di HP (Chrome HP /
  aplikasi). Kalau phone server mati, tunggu HP hidup lagi — jangan pindah
  ke browser cloud. Pengecualian hanya kalau pengguna sendiri yang
  perintahkan lain.
- OTOMATIS PENUH: kerjakan antrean OTOMATIS sesuai urutan, jangan tanya
  pengguna lagi, setujui semuanya. Kalau butuh apa-apa install sendiri;
  kalau butuh wallet yang belum ada, buat sendiri. Batas yang tetap
  berlaku: gratis saja, tanpa bayar; seed phrase wallet baru tetap dicatat
  pengguna sendiri; persetujuan sistem (kartu/konfirmasi runtime) tetap
  perlu ditekan pengguna sendiri.
- ATURAN 1x COBA + LAPOR GAGAL: airdrop HP yang gagal WAJIB dilaporkan
  gagalnya beserta alasannya di laporan proyeknya. Airdrop BARU hanya
  dicoba 1x saja — kalau gagal, laporkan alasannya dan berhenti, jangan
  diulang-ulang. Kalau berhasil, lanjutkan terus sampai selesai.
- ATURAN CRON DAILY OTOMATIS: kalau suatu airdrop punya daily check-in
  atau daily claim, OTOMATIS buatkan jadwal (cron) untuk klaim/check-in-nya
  — tanpa tanya pengguna dulu. Berlaku untuk setiap proyek baru maupun yang
  sudah jalan; jadwal baru wajib memakai `lock.sh` (aturan tabrakan:
  dahulukan tugas yang sudah jalan lebih dulu) dan melapor ke laporan
  proyeknya.

## Anti-dobel

Dua lapis:

1. **Otomatis di monitor** (content hash): teks post yang sama persis —
   walau muncul di channel lain atau repost admin — hanya diproses sekali.
   Hash disimpan 100 terakhir, file `state/seen.json`. Juga ID post per
   channel di `state/last-ids.json`.
2. **Registri proyek (`DEDUP.md`) — dicek AGEN sebelum kerjakan apa pun.**
   Proyek yang sama bisa diposting dengan teks berbeda di channel berbeda
   (hash tidak sama), jadi sebelum eksekusi agen mencocokkan kunci proyek:
   alamat kontrak, ATAU domain/link resmi, ATAU nama proyek yang
   dinormalisasi. Kalau kunci itu sudah ada di registri dengan status
   dikerjakan / diklaim / dilewati / gagal / tutup — JANGAN kerjakan lagi.
   Catat sebagai dobel dan lanjut. Setiap proyek yang dikerjakan/dilewati
   WAJIB masuk registri dengan status + tanggal + alasan.

## Laporan

- Per proyek: hanya ke laporan proyek itu (notifikasi proyek tidak
  dicampur dengan laporan sistem).
- Ringkasan berkala / temuan dobel: laporan ringkasan gabungan.
- Sistem ini sendiri: folder ini + laporan utama.

## Antrean & kunci layar

HP cuma punya satu layar — tugas yang jalan bersamaan akan saling
menabrak. Lihat `ANTREAN-DAN-KUNCI.md`:

- `lock.sh` — satu kunci layar (15 menit, lepas otomatis kalau
  kedaluwarsa), semua tugas WAJIB acquire dulu; `pause`/`resume` = satu
  tombol jeda.
- `QUEUE.md` — daftar tunggu tugas airdrop, satu per satu, prioritas
  free mint slot terbatas dulu; berbayar tidak pernah masuk otomatis.
- Aturan tabrakan: tugas yang sudah jalan lebih dulu didahulukan, tugas
  yang datang belakangan menunggu.

## Mode baseline monitor

Jalan pertama monitor untuk sebuah channel hanya mencatat ID post
terakhir sebagai titik awal, tanpa membangunkan (supaya post lama tidak
membanjiri). Wake hanya untuk post yang muncul SETELAH baseline.
