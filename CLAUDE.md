# CLAUDE.md — konteks proyek Lokana

File ini dibaca otomatis oleh Claude Code. Isinya ringkasan keputusan, konvensi, dan
jebakan yang sudah ditemukan, supaya pekerjaan bisa dilanjutkan tanpa mengulang diskusi.

## Proyek ini apa

**Lokana** ("melihat untukmu") adalah robot mini open source berbasis **ESP32-C3 Super Mini**
dengan **OLED 0.96" 128×64**. Dipakai sebagai gantungan kunci (**Mode Saku**) dan asisten
meja (**Mode Meja**). Produk ini dijual sekaligus open source (kode MIT, hardware CERN-OHL;
nama & logo Lokana adalah merek dan tidak ikut lisensi).

Bacaan wajib sebelum mengubah sesuatu yang besar:

| Dokumen | Isi |
|---|---|
| `README.md` | Fitur, roadmap, keputusan desain, batasan |
| `docs/ARCHITECTURE.md` | Lapisan firmware, layanan link, daya, partisi, aplikasi |
| `protocol/LOKANA_LINK.md` | Spesifikasi protokol Lokana Link v1 (kontrak firmware ↔ aplikasi ↔ desktop) |
| `firmware/README.md` | Cara build, pin, gestur, perintah serial, contoh modul |

## Keputusan yang sudah final

Jangan diubah tanpa persetujuan pemilik proyek (Wayan):

- **Tidak memakai Chronos** atau aplikasi pihak ketiga. Aplikasi sendiri: **Aplikasi Lokana**.
- **Android dulu**: semua fitur wajib jalan di Android. iPhone tetap didukung, dikerjakan belakangan.
- Aplikasi HP: **Flutter + Kotlin** (Kotlin untuk *foreground service* dan *NotificationListener*).
- Layar utama **128×64**. Varian 128×32 boleh tetap bisa di-build, tapi bukan prioritas tata letak.
- HP ↔ Lokana lewat **BLE**. PC ↔ Lokana lewat **USB serial dulu**, WiFi UDP menyusul. BLE tidak dipakai untuk data PC.
- **Tidak ada web portal maupun web flasher** di perangkat. Konfigurasi hanya lewat aplikasi (termasuk WiFi lewat BLE).
- Pembaruan firmware punya **tiga jalur**: Mode Update, build dari kode, OTA lewat aplikasi. Semua bersumber dari **GitHub Releases**.
- Quick start: **GitHub Pages** (`docs/`) + kartu Canva ber-QR di kemasan.
- Hardware tambahan (IR, MPU6050, sensor suhu, speaker) **ditunda**.
- Urutan kerja: **protokol → firmware → skrip uji PC → aplikasi Android → Lokana Desktop**.

Masih terbuka: mekanisme Mode Update (WiFi AP + unggah lewat browser HP, atau lewat USB).

## Struktur repo

```
firmware/   Lokana OS (PlatformIO, Arduino framework)
protocol/   spesifikasi Lokana Link + skrip uji Python (protocol/tools/lokana_link.py)
app/        Aplikasi Lokana (Flutter + Kotlin) — belum dimulai
desktop/    Lokana Desktop — belum dimulai
hardware/   skema, PCB, casing — belum dimulai
docs/       arsitektur, quick start (GitHub Pages)
```

## Build, upload, monitor (Windows)

Jalankan dari folder `firmware/`. Kalau `pio` tidak ada di PATH, pakai
`C:\Users\<nama>\.platformio\penv\Scripts\platformio.exe`.

```powershell
pio run -e supermini                 # build untuk hardware asli
pio run -e supermini -t upload       # upload ke board (COM6 biasanya)
pio device monitor -b 115200         # serial monitor + console
pio run -e wokwi                     # build untuk simulasi Wokwi
pio run -e supermini-091             # varian OLED 0.91" 128x32
```

- **Selalu sebutkan `-e supermini` saat upload.** Env `wokwi` memakai pin berbeda.
- **Tutup serial monitor sebelum upload.** Monitor memegang port COM dan upload akan gagal
  ("port doesn't exist" / "could not open port").
- Kalau port tidak muncul: tahan **BOOT**, tekan **RST**, lepas BOOT, lalu upload.
  Untuk menunggu port di PowerShell:
  `while (-not [System.IO.Ports.SerialPort]::GetPortNames()) { Start-Sleep -Milliseconds 500 }; pio run -e supermini -t upload`
- Setelah upload, tekan **RST** sekali kalau firmware tidak langsung jalan.
- "No serial data received" di tengah upload = koneksi USB tidak stabil. Coba ulang / ganti kabel.
- Sebelum menyatakan selesai: **`pio run -e supermini` dan `pio run -e wokwi` harus sama-sama sukses.**

## Hardware & pin

| Komponen | Pin | Catatan |
|---|---|---|
| OLED SSD1306 128×64 (I2C, 0x3C) | SDA GPIO8, SCL GPIO9 | Sama di Wokwi. Pindah dari 20/21 di v0.2 (OLED tidak terdeteksi di 20/21) |
| Tombol | Sensor sentuh TTP223 di GPIO3 (aktif HIGH) | Wokwi: tombol mekanis ke GND (`-DBTN_ACTIVE_LOW=1`). Tombol BOOT (GPIO9) tidak dipakai karena jadi SCL; jangan ditekan saat jalan |
| Buzzer pasif | GPIO10 | |
| LED bawaan | GPIO8 (= SDA) | Tidak dipakai firmware (`PIN_LED -1`); berkedip redup mengikuti lalu lintas I2C |
| Baterai | GPIO1 (pembagi tegangan 1:2) | Belum terpasang di prototipe (`PIN_BATT=-1`) |

Semua pin dan ukuran layar diatur di `firmware/include/config.h` dan bisa ditimpa lewat
`build_flags` di `platformio.ini`.

## Konvensi kode firmware

- **Fitur baru = modul baru** di `src/modules/` (turunan `Module`), didaftarkan di `main.cpp`.
  Jangan menambah logika fitur ke `core/`.
- Modul **tidak** membaca BLE/USB langsung. Pesan masuk → layanan link (`lklink`) → `events::post()` → modul.
  Data besar (teks) lewat penyimpanan layanan (`text_store`), event hanya memberi tahu.
- Callback NimBLE berjalan di task lain: jangan memanggil display/events dari sana. Titipkan ke
  stream buffer / variabel `volatile`, proses di `link_ble::update()` (loop).
- Layar sistem (pairing, cari kunci) = modul dengan `hidden() = true`, dibuka lewat event,
  ditutup dengan `core::back()`.
- **Non-blocking**: tidak ada `delay()` panjang di loop. Animasi memakai waktu (`now`).
- **Perbandingan waktu selalu bertanda**: `(int32_t)(now - t) > interval`. Pengurangan
  `unsigned` biasa pernah menyebabkan layar langsung mati dan animasi berhenti lebih cepat.
- Gambar memakai `SCREEN_W` / `SCREEN_H`, jangan angka 128/64/32 langsung.
- Hindari nama enum/macro umum seperti `OK`, `FAIL`, `IDLE` (bentrok dengan macro ESP-IDF).
  Pakai awalan, misal `ST_OK`.
- Output serial memakai `\r\n` (terminal Wokwi dan Windows).
- Teks di layar: font ASCII saja. String UI dalam Bahasa Indonesia, singkat.
- Acak memakai `esp_random()` (hardware RNG).
- Komentar kode dalam Bahasa Indonesia, singkat. Istilah teknis boleh tetap Inggris.

## Konvensi protokol

- `protocol/LOKANA_LINK.md` adalah **sumber kebenaran**. Kalau implementasi butuh perubahan,
  ubah spesifikasinya dulu (tambah baris di tabel Riwayat), baru kodenya.
- Nomor `type`, ID ekspresi, ID dadu, dan key pengaturan **tidak boleh dipakai ulang atau diurutkan ulang**.
  Ekspresi baru ditambahkan di akhir `enum Expression`.
- Field baru selalu ditambahkan **di akhir** payload.

## Jebakan yang sudah ditemukan

| Gejala | Penyebab | Cara cek / solusi |
|---|---|---|
| OLED berkedip sekali saat boot lalu gelap; perintah serial lambat diproses | **Kabel jumper buruk**, OLED hilang dari bus I2C | `info` → "kirim frame" harus puluhan ms, bukan ratusan/ribuan. `scan`, `oled` untuk cek ulang. Ganti kabel dulu |
| Log boot tidak terlihat | USB CDC baru tersambung setelah setup jalan | `setup()` menunggu Serial maks 3 detik; buka monitor lalu tekan RST |
| `E (149) esp_core_dump_flash: Incorrect size…` | Belum ada partisi coredump (v0.1) | Hilang sejak `partitions.csv` v0.2. Kalau masih muncul, pastikan tabel partisi ikut ter-upload |
| `'namespace link' redeclared as different kind of symbol` | `link()` dari `unistd.h` (POSIX) | Namespace layanan bernama `lklink` |
| Frame USB besar (>256 B) hilang, tanpa ACK | Buffer RX USB CDC bawaan 256 B meluap saat loop sibuk | `Serial.setRxBufferSize(2048)` sebelum `Serial.begin()` |
| Firmware baru crash tapi tidak rollback | Arduino menandai app valid sebelum `setup()` | `docs/ARCHITECTURE.md` §2.7: timpa `verifyRollbackLater()` saat OTA dibuat |
| Teks bertangga di terminal | Hanya `\n` | Pakai `\r\n` |
| Di Wokwi GPIO20/21 dipakai serial | Pin I2C bentrok | Sejak v0.2 semua env memakai I2C 8/9 |
| Serial diam setelah upload (port ada, `info` tidak dibalas) | DTR/RTS saat port dibuka | Skrip pyserial: buka dengan `dtr=False, rts=False`, tunggu ±1 dtk, lalu `dtr=True` |

Perintah diagnostik console: `info`, `scan`, `oled`, `i2c <kHz>`, `ble`, `help`.
Uji protokol dari PC: `python protocol/tools/lokana_link.py test` (tutup serial monitor dulu).

## Status & tugas berikutnya

- **v0.1 ✅** Fondasi: driver, core, sistem modul, modul Lokana/Jam/Dadu, console, diagnostik I2C.
- **v0.2 ✅** Layar 128×64 + partisi. Lulus uji hardware 2026-11-16: OLED (SDA 8 / SCL 9) dan TTP223 GPIO3
  (tap/double/triple/long terbaca). Tampilan Wokwi belum dicek terpisah.
  Tata letak 32 px dipertahankan di cabang `#if SCREEN_H >= 64 … #else`. Rollback: lihat §2.7.
  Rincian tugas awal (sudah dikerjakan):
  1. `config.h`: default `SCREEN_H 64` dan `PANEL_H 64`. Sediakan env `supermini-091` untuk varian 128×32.
  2. `platformio.ini`: perbarui komentar header, tambahkan `board_build.partitions = partitions.csv`.
  3. Buat `firmware/partitions.csv` sesuai tabel di `docs/ARCHITECTURE.md` §2.6.
  4. Tata letak ulang untuk 128×64: face engine (mata lebih tinggi, ruang untuk efek),
     Jam (digit besar + baris tanggal), Dadu (pips lebih besar), menu (beberapa baris sekaligus),
     toast, layar info, splash.
  5. Cek apakah bootloader Arduino-ESP32 2.0.17 mendukung *app rollback*; catat hasilnya di `docs/ARCHITECTURE.md` §2.7.
  6. `FW_VERSION` → `0.2.0`; perbarui status roadmap di `README.md`.
  7. Uji di Wokwi (OLED-nya sudah 128×64) dan hardware asli.
- **v0.3 ✅** Lokana Link. Lulus 24/24 uji otomatis USB; pairing + bonding BLE lulus di HP (nRF Connect) 2026-11-16:
  `services/link*` (parser, USB envelope + console di port yang sama, BLE NimBLE 1.4.3 dengan
  passkey DisplayOnly + bonding), modul Teks (slot 1–8 di NVS), layar Pairing & Cari (FIND_KEYS),
  `protocol/tools/lokana_link.py`. Pesan v0.3: HELLO, TIME_SYNC, DEVICE_INFO, ACK, FIND_KEYS,
  EXPRESSION, GOTO, CUSTOM_TEXT. Belum diuji: tampilan di Wokwi. MTU dari nRF Connect tetap 23 (frame dipecah per 20 B).
- **v0.4** Aplikasi MVP (Flutter + Kotlin) + pesan SETTINGS, DICE, BUTTON, BITMAP, FIND_PHONE.

## Cara berkomunikasi dengan pemilik proyek

- Gunakan **Bahasa Indonesia**. Saat memakai istilah teknis Indonesia, sertakan istilah
  Inggrisnya, contoh: tata letak (*layout*), pembaruan firmware (*firmware update*).
- Jelaskan hasil uji yang perlu dilihat langsung di hardware (apa yang harus tampil di OLED).
- Minta konfirmasi sebelum mengubah keputusan di bagian "Keputusan yang sudah final".
