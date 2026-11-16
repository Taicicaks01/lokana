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
app/        Aplikasi Lokana Android (Flutter UI + Kotlin BLE), lihat app/README.md
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

### Aplikasi (folder `app/`)

Flutter ada di `C:\Users\<nama>\dev\flutter` (shallow clone 3.50.0), JDK 21 di `C:\Users\<nama>\dev\jdk-21.0.13+9`
(keduanya belum di PATH; sudah didaftarkan lewat `flutter config --jdk-dir/--android-sdk`).

```powershell
flutter analyze                               # harus "No issues found"
flutter test                                  # uji codec Lokana Link (byte asli firmware)
flutter build apk --release --split-per-abi   # HP modern: app-arm64-v8a-release.apk (±16 MB)
```

- Flutter 3.47+: impor `package:material_ui/material_ui.dart` (paket resmi flutter.dev),
  bukan `package:flutter/material.dart` (deprecated).
- Build Android pertama mengunduh Gradle, NDK 28.2, dan CMake (dipaksa Flutter Gradle plugin walau
  tidak ada kode native). Di koneksi lambat ±80 menit; build berikutnya jauh lebih cepat.

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
  Pesan keluar tanpa diminta (hasil dadu, BUTTON, FIND_PHONE, REPORT) lewat fungsi `lklink::report*()` /
  `lklink::findPhone()`; layanan yang memutuskan host mana yang boleh menerima (sesi setelah HELLO).
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

## Konvensi aplikasi (app/)

- BLE, framing, `seq`/ACK, dan Cari HP ada di **Kotlin** (`BleLink.kt`, `LinkService.kt`, `Alarm.kt`).
  Dart hanya membuat/membaca payload (`lib/link/proto.dart`) dan menampilkan UI.
- **Jangan menambah plugin BLE** (`flutter_blue_plus` 2.x berlisensi berbayar dan *ping* saat build).
  Usahakan tanpa dependensi Dart pihak ketiga; fitur Android lewat Kotlin + MethodChannel.
- Payload baru: tambahkan builder/parser di `proto.dart` **dan** uji byte-nya di `test/proto_test.dart`
  (bandingkan dengan `lokana_link.py` atau balasan asli firmware).
- Teks UI Bahasa Indonesia. Hindari API Flutter yang sudah *deprecated* (`withOpacity`,
  `MaterialStateProperty`, `DropdownButtonFormField.value`).

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
| APK ditolak Play Protect saat dipasang dari file manager/WhatsApp | Perlindungan penipuan Google di Indonesia memblokir aplikasi *sideload* yang memakai izin baca notifikasi; APK juga masih bertanda tangan *debug* | Pasang lewat `adb install -r` (USB debugging), atau matikan sementara Play Protect. Jangka panjang: kunci rilis + Google Play |
| Uji widget Flutter: frame dari EventChannel tiruan tidak sampai | *Fake async* `testWidgets` | Bungkus penantian dengan `tester.runAsync`, atau uji logika link dengan `test()` biasa |
| Serial diam setelah upload (port ada, `info` tidak dibalas) | DTR/RTS saat port dibuka | Skrip pyserial: buka dengan `dtr=False, rts=False`, tunggu ±1 dtk, lalu `dtr=True` |

Perintah diagnostik console: `info`, `scan`, `oled`, `i2c <kHz>`, `ble`, `help`.
Uji protokol dari PC: `python protocol/tools/lokana_link.py test` (tutup serial monitor dulu).
Perintah console di USB menghentikan pesan tanpa diminta ke USB sampai `HELLO` berikutnya (spesifikasi §3.2),
jadi uji BUTTON butuh sentuhan sungguhan (`test --touch`), bukan perintah `tap`.

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
- **v0.4 ✅** Firmware 0.4.0 lulus 58/58 uji USB; aplikasi diuji di HP Android 2026-11-16: SETTINGS (key `0x06 button_events` sesi saja,
  nama pemilik di NVS), DICE (hasil dikirim tiap lemparan), BUTTON, FIND_PHONE (menu "Cari HP" + layar
  Memanggil HP; `op 0` dari HP menutup layar), BITMAP (modul Gambar, slot di littlefs `/bmp/N.bin`).
  Aplikasi Android di `app/` (codec Dart diuji, BLE Kotlin): sambung/pairing, ekspresi, teks, emoji, dadu,
  cari kunci, pengaturan jalan. Belum diuji: Wokwi.
- **Backlog (dibereskan sekaligus, atas permintaan Wayan):**
  - Dialog pairing Android (Infinix) memakai kolom PIN generik ("Usually 0000 or 1234") meski kodenya
    6 digit dari OLED: dari sistem, tidak bisa diubah; pertimbangkan CompanionDeviceManager.
  - **Redesain UI/UX menyeluruh** (aplikasi & OLED: bahasa desain, ikon 1-bit, status bar, transisi), lalu
    perbaikan bug per modul memakai Layar Lokana + screenshot.
- **v0.5 ✅** Notifikasi (2026-11-16). Firmware 0.5.0 lulus 107/107 uji USB; aplikasi diuji di HP 2026-11-17. Firmware 0.5.0: `NOTIF` (notif_store RAM maks 8, modul Notif
  setelah Jam, popup 6/10 dtk), `CALL` (layar Panggilan tersembunyi, dering `MEL_CALL`, tap = bisukan),
  `core/text_wrap.h` (dipakai Teks & Notif). Aplikasi 0.5.0: `NotifListener.kt` (filter aplikasi di
  `NotifPrefs`, panggilan dari CallStyle/full-screen intent tanpa izin telepon), halaman Notifikasi,
  `BleLink.resume()` (sambung otomatis kecuali pengguna memutus). Build semua env + APK lulus.
  Tambahan v0.5 (hasil uji v0.4 di HP): nama Bluetooth = `device_name` (UTF-8, bawaan `Lokana_लोचन-01`,
  `BLE_NAME_DEFAULT` di config.h; OLED lewat `core/oled_text` Dewanagari → Latin), `0x06 UNPAIR` + deteksi bond
  lama di aplikasi (`BleLink.forget`, `removeBond` via refleksi, fallback ke Pengaturan Bluetooth), `FIND_KEYS`
  D→H, `0x32 ANIM` (galeri `/img/N.bin` dipakai bersama BITMAP, `image_store` menggantikan `bitmap_store`),
  halaman Emoji & Gambar baru (potong rapat, 7 efek, GIF + dithering, galeri dengan pratinjau),
  `0x33 SCREEN` (mirror layar hanya saat berubah ≤ 10 fps, berhenti sendiri 30 dtk tanpa START, screenshot,
  gestur jarak jauh lewat `core::injectGesture`; halaman **Layar Lokana** + screenshot ke Pictures/Lokana),
  tema aplikasi (`lib/theme.dart`: Sistem/Terang/Gelap, 7 warna aksen, warna piksel pratinjau OLED).
  Rapikan OLED setelah uji: ikon gagang telepon bitmap 22x22, header Info = nama Lokana, nama modul saat
  berganti jadi label kecil di atas (`core::goTo(name, announce)`; modul yang membuka diri karena event
  memakai `announce = false`, layar tersembunyi tidak pernah diumumkan). Belum diuji: Wokwi.
- **v0.5.1 ✅** Splash boot **लोचन** (2026-11-17), firmware **dan** aplikasi: garis atas (shirorekha) tumbuh →
  huruf turun → matra ो → LOKANA → kilau → kembali ke garis → garis terbelah jadi dua mata terpejam di posisi
  mata Face (open 0.05) → wajah membuka mata. Firmware: `modules/splash_module` (modul tersembunyi, berjalan
  di loop sehingga BLE/console aktif selama animasi; tap = lewati; console `splash [ms]`), bitmap
  `modules/splash_art.h` dari `firmware/tools/gen_splash.py`. Font **Baloo 2** (OFL) di `app/assets/fonts/`
  dipakai bersama. Boot tidak lagi menunggu serial 3 dtk saat USB tidak tersambung ke komputer
  (`HWCDC::isPlugged()`). Aplikasi 0.5.1: `lib/splash.dart`, setelan di Tampilan aplikasi, latar launch hitam.
  Lulus 107/107 uji USB; frame splash dicek lewat `splash <ms>` + SCREEN CAPTURE. Disetujui Wayan.
- **v0.5.2 ✅** Permintaan Wayan setelah uji v0.5 (2026-11-17): SETTINGS `0x07 notif_popup` (detik, 0 = tidak
  muncul; NVS `npop`), **Cari HP jadi modul biasa** (setelah Notif; dihapus dari menu; tap = bunyikan/hentikan),
  `CUSTOM_TEXT font` (5 font, field akhir opsional; slot NVS menyimpan font di 4 bit atas byte ukuran),
  `wrapTextPx` (bungkus kata berdasar lebar piksel), teks panjang mulai dari atas lalu bergulir. Aplikasi 0.5.2:
  pilihan font + Enter = kirim di halaman Teks, "Lama tampil di Lokana" di halaman Notifikasi, nada Cari HP
  (nada HP / file audio, `Alarm.kt`). Lulus 126/126 uji USB. Diuji di HP 2026-11-17: berfungsi.
- **v0.5.3 ✅** Permintaan Wayan setelah uji v0.5.2 (2026-11-17): `0x34 TEXT_SLOT` (LIST → 8 ITEM dicicil di
  `pumpTextOut`, SHOW; bit `caps` 14), SETTINGS `0x08 boot_guide` (NVS `guide`), modul tersembunyi **Panduan**
  (`guide_module`, `remoteOpen()` = boleh lewat GOTO), sub-menu Panduan di menu Lokana, `core::goToLater`.
  Aplikasi 0.5.3: redesain UI (`lib/ui.dart`, tema Baloo 2), pratinjau teks persis Lokana (`oled_text.dart` +
  `oled_fonts.dart` dari `firmware/tools/gen_oled_fonts.py`), slot teks di aplikasi, halaman Cara pakai,
  perbaikan thumbnail galeri meluber, setelan Teks/Gambar diingat. Lulus 146/146 uji USB, 32 uji Flutter.
  Diuji di HP 2026-11-17 (dipasang lewat adb): semua berfungsi.
- **v0.6** Navigasi Google Maps: NAV (ikon panah dari notifikasi Maps → bitmap 1-bit), modul Navigasi.

## Cara berkomunikasi dengan pemilik proyek

- Gunakan **Bahasa Indonesia**. Saat memakai istilah teknis Indonesia, sertakan istilah
  Inggrisnya, contoh: tata letak (*layout*), pembaruan firmware (*firmware update*).
- Jelaskan hasil uji yang perlu dilihat langsung di hardware (apa yang harus tampil di OLED).
- Minta konfirmasi sebelum mengubah keputusan di bagian "Keputusan yang sudah final".
