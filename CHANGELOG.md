# Catatan perubahan

Semua perubahan penting di Lokana: firmware **Lokana OS**, **Aplikasi Lokana** (Android), protokol
**Lokana Link**, dan hardware. Format mengikuti [Keep a Changelog](https://keepachangelog.com/id-ID/1.1.0/);
versi firmware dan aplikasi berjalan bersama (`0.MINOR.PATCH`). Detail protokol ada di tabel Riwayat
`protocol/LOKANA_LINK.md`.

## [Belum dirilis]

### Firmware: manajemen daya — Lokana OS 0.5.7 (bertahap)
- CPU 80 MHz (sebelumnya 160 MHz): layar mati + HP tersambung 30 → 22 mA. Tabel ukur tiap langkah di
  `docs/ARCHITECTURE.md` §2.5. `info` menampilkan frekuensi CPU.
- BLE hemat: iklan 1 detik setelah 1 menit tanpa koneksi (cepat lagi saat layar dinyalakan), interval koneksi 125 ms +
  latency 3 saat layar mati (22 ms saat menyala/OTA/mirror). Layar mati + HP tidak tersambung 27 → 22 mA.
  Perintah `ble` menampilkan parameter koneksi.

### Firmware & aplikasi: baterai — Lokana OS 0.5.6
- Tegangan baterai dibaca di GPIO1 (env `supermini`), persen asli dikirim ke aplikasi, plus tegangan (`battery_mv`) dan
  status **mengisi** (charger di GPIO4) / **lemah**. Lokana memberi tahu aplikasi sendiri saat status baterai berubah.
- OLED: ikon baterai di Jam, lencana pojok saat lemah atau mengisi, toast "Mengisi daya" / "Baterai lemah".
- Di bawah 3,40 V Lokana menampilkan "Baterai habis" lalu tidur dalam (*deep sleep*); sentuh untuk menyalakan.
- Kalibrasi per unit lewat console `batt cal <volt>`; perintah bring-up `tone`, `sweep`, `adc`, `btnraw`.
- Aplikasi: chip baterai di Beranda dan kartu perangkat Pengaturan (ikon level, mengisi, lemah).
- Hardware: pin OLED jadi SDA GPIO9 / SCL GPIO8; nada Cari kunci 1300/1500 Hz (resonansi buzzer).
- **OTA lewat BLE dari HP diuji di Lokana Cube**: ±90 detik untuk 1,2 MB (sebelumnya ±8 menit; aplikasi menulis tanpa
  respons dan meminta koneksi prioritas tinggi selama kirim). Perbaikan: aplikasi tidak lagi melaporkan "gagal menyala"
  untuk firmware yang sehat; `END` yang terkirim ulang dibalas OK.

### Firmware & aplikasi: pembaruan firmware lewat aplikasi (OTA) — Lokana OS 0.5.5
- Pesan `OTA` diaktifkan (bit `caps` 6): firmware dikirim lewat BLE dari aplikasi atau USB dari PC, diperiksa SHA-256,
  lalu dipasang ke slot cadangan.
- **Rollback otomatis**: firmware baru diuji ±10 detik setelah restart; kalau crash, macet, atau layar tidak menyala,
  Lokana kembali sendiri ke versi lama dan memberi tahu di layar.
- Aplikasi: Pengaturan → **Pembaruan firmware** (rilis GitHub atau file `.bin`, progres, hasil berhasil/rollback).
- Alat PC: `lokana_link.py ota FILE`; uji `test_v055`.

### Aplikasi: desain baru "robot hidup" (`docs/DESIGN.md`)
- **Ikon baru** konsep kubus + gantungan dari `brand/` (adaptive icon, themed icon Android 13+, ikon notifikasi);
  warna bawaan jadi pink `#F478AA`, latar pembuka `#1A161E`.
- **Token warna & tema** (`lib/tokens.dart`): permukaan, teks, dan garis dari token; pink brand hanya untuk satu aksi
  utama per layar; judul Baloo 2; kartu radius 24, tombol pil.
- **Lokana Cube** (`lib/cube.dart`): gambar perangkat yang hidup dengan mood siaga, mencari, mengantuk, senang.
- **4 tab**: Beranda · Studio (Teks/Gambar/Ekspresi/Dadu) · Terhubung (Ketinggalan/Notifikasi/Cari HP) · Pengaturan.
- **Beranda**: hero Lokana Cube + chip sinyal dari RSSI asli, aksi cepat (Cari kunci, Sinkron jam, Layar), remote
  Tap/2×/Tahan, kisi Studio dengan thumbnail OLED asli.
- **Studio**: pratinjau OLED dengan glow, grid piksel, dan label 128×64; `SlotGrid` 4×2 untuk slot teks & gambar;
  "Kirim ke" = Tampilkan sekarang / Simpan ke slot.
- **Terhubung**: radar ketinggalan (cincin mengikuti RSSI); Cari HP + pilihan nada pindah dari Pengaturan.
- **Pengaturan**: kartu perangkat, nama Bluetooth lewat lembar bawah, kerangka abu-abu saat memuat.
- **Sambungkan**: Cube melirik saat mencari, kartu perangkat dengan bar sinyal.
- **Poles**: semua kirim berhasil = getar ringan + Lokana Cube tersenyum; Ekspresi tanpa emoji (wajah asli dari
  geometri firmware); kerangka menggantikan spinner; menghormati "kurangi animasi"; diuji mode terang + huruf 130%.

### Hardware
- **Case Lokana Cube v1.1** (`hardware/case/`): skrip Fusion parametrik, STL badan & tutup, STEP, diagram wiring,
  dan urutan rakit. Status: prototipe uji pas.

## [0.5.4] - 2026-11-17
### Ditambahkan
- **Pengingat ketinggalan dua arah.** HP berbunyi jika Lokana tertinggal (status GATT 8 + RSSI terakhir lemah,
  waktu tunggu 10–60 dtk, bunyi/getar, Matikan / Jeda 1 jam); Lokana berbunyi dan menampilkan "HP-mu tertinggal?"
  jika HP tertinggal (alasan putus `0x208`, RSSI < −70 dBm, 20 dtk).
- SETTINGS `0x09 leave_alert`; `GOTO "Tertinggal"` untuk uji; console `left`.
- Aplikasi: halaman Pengingat ketinggalan.
### Diperbaiki
- Aplikasi menyambung ulang otomatis setelah Bluetooth HP dimatikan lalu dinyalakan.

## [0.5.3] - 2026-11-17
### Ditambahkan
- Pesan `0x34 TEXT_SLOT`: aplikasi bisa membaca, menampilkan, mengubah, dan mengosongkan slot teks 1–8.
- **Panduan cara pakai** di OLED setelah splash boot (SETTINGS `0x08 boot_guide`, sub-menu Panduan, `GOTO "Panduan"`).
- Aplikasi: pratinjau teks **sama persis** dengan layar Lokana (font OLED disalin dari firmware, diuji piksel demi
  piksel), halaman Cara pakai, setelan Teks/Gambar diingat, redesain UI pertama.
### Diperbaiki
- Thumbnail galeri gambar tidak lagi keluar dari bingkai.

## [0.5.2] - 2026-11-17
### Ditambahkan
- SETTINGS `0x07 notif_popup` (lama notifikasi tampil, 0 = tidak muncul).
- `CUSTOM_TEXT` field `font`: 5 font (Piksel, Sans, Sans Tebal, Serif, Mono Tebal); teks panjang bergulir.
- Aplikasi: pilihan font, Enter = kirim, nada Cari HP (nada HP / file audio).
### Diubah
- **Cari HP** jadi modul biasa di Lokana (tap = bunyikan/hentikan HP), bukan item menu.

## [0.5.1] - 2026-11-17
### Ditambahkan
- Splash boot **लोचन** di Lokana dan aplikasi (font Baloo 2): huruf turun dari garis atas, lalu garis terbelah
  menjadi mata Lokana.
- Boot tidak lagi menunggu serial 3 detik saat USB tidak tersambung ke komputer.

## [0.5.0] - 2026-11-17
### Ditambahkan
- **Notifikasi HP** (`NOTIF`, modul Notif) dan **panggilan masuk** (`CALL`), filter per aplikasi di HP.
- `0x32 ANIM`: animasi bingkai & galeri gambar slot 1–8; halaman Emoji & Gambar (GIF, dithering, 7 efek).
- `0x33 SCREEN`: Layar Lokana langsung di HP, screenshot, gestur jarak jauh.
- `0x06 UNPAIR` + deteksi pairing lama; nama Bluetooth bawaan `Lokana_लोचन-01`; tema aplikasi.
- `FIND_KEYS` dua arah (Lokana melapor saat bunyi mulai/berhenti).

## [0.4.0] - 2026-11-16
### Ditambahkan
- **Aplikasi Lokana Android** (MVP): sambung + pairing kode 6 digit, ekspresi, teks, emoji, dadu, cari kunci, pengaturan.
- Pesan `SETTINGS`, `DICE`, `BUTTON`, `FIND_PHONE` (Cari HP), `BITMAP` (modul Gambar).

## [0.3.0] - 2026-11-16
### Ditambahkan
- **Lokana Link v1** lewat USB dan BLE (NimBLE, passkey 6 digit di OLED + bonding), dengan skrip uji PC
  `protocol/tools/lokana_link.py`.
- Pesan `HELLO`, `TIME_SYNC`, `DEVICE_INFO`, `ACK`, `FIND_KEYS`, `EXPRESSION`, `GOTO`, `CUSTOM_TEXT`.
- Modul Teks (slot 1–8 di NVS), layar Pairing dan Cari kunci.
- Fondasi dari v0.1–v0.2: sistem modul, wajah Lokana, Jam, Dadu, console, layar 128×64, tabel partisi.

[Belum dirilis]: https://github.com/Taicicaks01/lokana/compare/1b0aa28...HEAD
[0.5.4]: https://github.com/Taicicaks01/lokana/commit/1b0aa28
[0.5.3]: https://github.com/Taicicaks01/lokana/commit/d85a074
[0.5.2]: https://github.com/Taicicaks01/lokana/commit/d85a074
[0.5.1]: https://github.com/Taicicaks01/lokana/commit/5e10df6
[0.5.0]: https://github.com/Taicicaks01/lokana/commit/1ccb9d6
[0.4.0]: https://github.com/Taicicaks01/lokana/commit/3344d88
[0.3.0]: https://github.com/Taicicaks01/lokana/commit/79b179d
