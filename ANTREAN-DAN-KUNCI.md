# Antrean & kunci layar HP — desain

Masalah yang dipecahkan: beberapa tugas terjadwal (cron) dan tugas antrean
yang jalan bersamaan akan saling menabrak di satu layar HP — layar
lompat-lompat, klaim tertunda, deploy terganggu. Aturan "tugas yang jalan
duluan didahulukan" perlu ditegakkan otomatis, bukan dicek manual lewat
screenshot.

## Tiga bagian

### 1. Satu kunci layar — `lock.sh`

Semua tugas yang mau menyentuh HP WAJIB pegang kunci dulu:
`lock.sh acquire <owner> "<tugas>"`. Yang tidak dapat kunci, diam dan coba
lagi putaran berikut — tidak boleh tap apa pun.

- Kunci berlaku 15 menit, lalu lepas sendiri (tugas yang mati di tengah
  jalan tidak memacetkan sistem). Pemegang yang sama boleh perpanjang.
- Hanya pemegangnya yang boleh melepas (`lock.sh release <owner>`).
- `lock.sh status` menampilkan siapa yang sedang memegang layar.
- Batasan jujur: kunci ini file di mesin agen, bukan pengunci Android.
  Worker yang tidak memanggil `lock.sh` tetap bisa menabrak — jadi semua
  jadwal (cron) HARUS diubah untuk memanggilnya (lihat Aktivasi).

### 2. Daftar tunggu — `QUEUE.md`

Setiap link/tugas airdrop masuk antrean dulu, dikerjakan satu per satu,
maksimal 15 menit per tugas, gagal 1x berstatus GAGAL dan dilaporkan.
Prioritas: free mint slot terbatas dulu, baru whitelist gratis, baru misi
XP/poin gratis. Berbayar tidak pernah masuk antrean otomatis.

### 3. Satu tombol jeda — `lock.sh pause / resume`

`lock.sh pause "<alasan>"` membuat semua acquire gagal — semua tugas HP
berhenti sampai `lock.sh resume`. Pengguna tidak perlu mematikan jadwal
satu-satu lagi saat ingin semua tugas diam.

## Yang HARUS dilakukan tiap worker (cuplikan untuk ditempel ke jadwal)

Di AWAL tiap putaran, sebelum screenshot/tap apa pun:

```
./lock.sh acquire worker-a "klaim/deploy tugas" \
  || exit 0   # layar dipakai tugas lain / jeda aktif — diam, coba putaran berikut
# ... kerja seperti biasa ...
./lock.sh release worker-a
```

Ganti `worker-a` dengan nama worker/tugas yang sesuai. Kalau worker mati
di tengah jalan tanpa release, kunci lepas sendiri setelah 15 menit.

## Aktivasi

1. Tempel cuplikan di atas ke definisi setiap jadwal (cron) yang
   menyentuh HP.
2. Tugas antrean (`QUEUE.md`) dikerjakan oleh satu worker yang sama
   polanya: ambil tugas MENUNGGU paling atas, acquire kunci `antrean`,
   kerjakan maks 15 menit, release, update status di `QUEUE.md`.
3. Tidak perlu jadwal baru untuk ini — jadwal yang sudah ada tetap pada
   waktunya; yang berubah hanya mereka saling menunggu lewat kunci.

## Catatan

- Antrean tidak bikin tugas lebih cepat: HP cuma satu layar, tugas tetap
  satu per satu. Yang berubah: tidak ada lagi yang rebutan layar, dan
  pengguna bisa lihat urutannya di `QUEUE.md`.
