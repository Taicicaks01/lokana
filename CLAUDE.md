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
  *Keputusan 2026-11-17:* **selesaikan Android dulu sesuai rencana awal**, baru masuk iPhone (rencananya sudah
  ada di "Fase iPhone" bawah, jangan dikerjakan sebelum Wayan bilang mulai). Wayan **tidak punya Mac**.
- **Kualitas aplikasi**: targetnya lebih bagus dari aplikasi wearable di pasaran. Ikuti `docs/DESIGN.md`.
- Ikon aplikasi: **konsep E, kubus + gantungan**. Sumber ada di `brand/` (jangan gambar ulang manual).
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
hardware/   casing Lokana Cube v1.1 (hardware/case/); skema & PCB belum dimulai
docs/       arsitektur, quick start (GitHub Pages)
brand/      ikon & aset merek (Android, iOS, Play Store, web) + generator brand/tools/gen_icons.py
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
| OLED SSD1306 128×64 (I2C, 0x3C) | SDA GPIO9, SCL GPIO8 | **Ditukar 2026-11-21** (keputusan Wayan, ikut wiring unit 1). Wokwi tetap 8/9 lewat `build_flags`. Pindah dari 20/21 di v0.2 |
| Tombol | Sensor sentuh TTP223 di GPIO3 (aktif HIGH) | Wokwi: tombol mekanis ke GND (`-DBTN_ACTIVE_LOW=1`). Tombol BOOT (GPIO9) tidak dipakai karena jadi SDA; jangan ditekan saat jalan |
| Buzzer pasif 9×5.5 | GPIO10 → R 1k → Q1 S8050 (NPN); unit pertama: 2SC1815 SOT-23 + R 1.2k | Buzzer + ke 3V3, − ke kolektor Q1, emitor ke GND, D3 SS14 paralel buzzer. Jangan drive langsung dari GPIO (kumparan ±16 Ω). Logika firmware tidak berubah. Daftar komponen: `hardware/BOM.md` |
| LED bawaan | GPIO8 (= SCL) | Tidak dipakai firmware (`PIN_LED -1`); berkedip redup mengikuti lalu lintas I2C |
| Baterai | GPIO1 (R1 100k / R2 100k + 100 nF ke GND; unit pertama 220 nF) | Dipasang **setelah saklar, sebelum D1** (tegangan sel asli). Firmware: `-DPIN_BATT=1` di env `supermini` (sejak 0.5.6); faktor per unit `batt cal <V>` (NVS) |
| Deteksi charge (opsional) | GPIO4 (100k/100k dari IN+ TP4056) | `-DPIN_CHG=4` (0.5.6). Baca dengan **ADC**: > 2.0 V dicolok, < 1.5 V dicabut. Jangan sebagai input digital (±2,5 V, batas VIH) |

**Jalur daya (case v1.1):** LiPo 102530 → TP4056 Type-C + DW01A (Rprog **2.7 kΩ** ≈ 440 mA, keputusan Wayan 2026-11-19; cadangan 3.3 kΩ kalau terlalu panas) → OUT+ → saklar
SS12D00 → **D1 Schottky** → pin 5V Super Mini. GND sistem dari **OUT−**. Opsional **D2**: 5V Super Mini → IN+ TP4056
(port program ikut mengisi). Karena D1 (±0.3 V), regulator 3.3 V mulai kurang tegangan saat sel ±3.5 V.
Port: USB-C **kanan** = Super Mini (program/data), USB-C **bawah** = TP4056 (charge), saklar di **kiri**.
Detail, gambar wiring, dan urutan rakit: `hardware/case/README.md`, `lokana_wiring.png`, `lokana_urutan_rakit.png`.
Case parametrik Fusion: `hardware/case/lokana_case_v1.py` (dokumen Fusion "Lokana Cube v1", project RnD).

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
| Aplikasi tidak menyambung lagi setelah Bluetooth HP dimatikan-nyalakan | Percobaan `connectGatt` saat adapter mati gagal diam-diam | Sejak 0.5.4 `BleLink` mendengarkan `ACTION_STATE_CHANGED` dan menyambung ulang saat `STATE_ON` |
| Uji Lokana tanpa BLE (pengingat ketinggalan di HP) | — | `python -m esptool --port COM9 --after no_reset read_mac` menahan Lokana di bootloader; `--after hard_reset` menjalankannya lagi |
| Versi di header firmware = "esp-idf: v4.4.7…", bukan versi Lokana | Pustaka Arduino prebuilt mengisi `esp_app_desc_t.version` | Pakai penanda `LOKANA_OS_VERSION:` (`services/ota.cpp`); simbol harus **dipakai** kode (linker `--gc-sections` membuang simbol tak terpakai walau `used`) |
| OTA: data acak ditolak di CHUNK pertama, bukan di END | `esp_ota_write` memeriksa byte `0xE9` di tulisan pertama | Sudah dipetakan ke ABORT alasan 6; data uji harus diawali `0xE9` untuk menguji pemeriksaan di END |
| Layar sistem (Tertinggal) langsung tertutup, kadang-kadang | `uint32_t t = now - _since` di `update(now)`: `enter()` memakai `millis()` yang bisa 1 ms lebih baru dari `now` loop → meluap → `t >= SHOW_MS`. Makin sering di CPU 80 MHz | Selalu `int32_t t = (int32_t)(now - x)` dan anggap negatif = 0 (diperbaiki 0.7 di `left_module`, `notif_module`, `guide_module` `elapsed()`, `splash_module` `elapsed()`, `clock.cpp`). Gejala uji: "Panduan tampil" / "layar Tertinggal tampil" gagal acak |
| Pengaturan / GOTO / toast dari HP hilang saat layar Lokana mati | Jalur layar-mati di `core::loop` dulu hanya meneruskan event ke modul lalu `return` | Sejak 0.7: event membangunkan layar lalu diproses jalur biasa (`events::pending()`); uji regresi di `test_v07` |
| Uji widget Flutter: frame dari EventChannel tiruan tidak sampai | *Fake async* `testWidgets` | Bungkus penantian dengan `tester.runAsync`, atau uji logika link dengan `test()` biasa |
| OTA lewat BLE 8 menit (±2,4 KB/s) | Kotlin menulis dengan *write with response* + interval koneksi bawaan | Sejak 0.5.6: `WRITE_TYPE_NO_RESPONSE` (karakteristik RX punya `WRITE_NR`) + `requestConnectionPriority(HIGH)` selama OTA → ±90 dtk |
| Aplikasi bilang OTA "gagal menyala" padahal firmware baru sehat | `link.info` tidak dikosongkan saat putus; halaman Update membaca versi lama begitu tersambung lagi | Sejak 0.5.6 tunggu `link.infoCount` naik (DEVICE_INFO baru) sesudah putus. END ulang dibalas OK oleh firmware |
| Upload PlatformIO gagal "No serial data received" di tahap stub | Sambungan USB goyah (HP juga tercolok ke laptop) | `python -m esptool --chip esp32c3 --port COMx --no-stub write_flash 0x10000 .pio/build/supermini/firmware.bin` (±73 dtk), atau ganti port USB |
| Serial diam setelah upload (port ada, `info` tidak dibalas) | DTR/RTS saat port dibuka; atau chip tertahan di mode download setelah reset esptool | Skrip pyserial: buka dengan `dtr=False, rts=False`, tunggu ±1 dtk, lalu `dtr=True`. Kalau `esptool --before no_reset --after no_reset read_mac` menjawab, chip di bootloader: cabut-colok USB / tekan RST |
| GPIO1 terbaca ±2,5 V (≈ 5 V) saat saklar OFF + USB | **D1 tidak terpasang**: pembagi ikut 5V USB, dan saklar ON + USB mengisi LiPo langsung | Pasang D1 (anoda ke saklar, katoda ke pin 5V); pembagi di sisi saklar. `adc` untuk cek |
| Tahan (`long`) tidak terdeteksi, tap terbaca jadi `double` | Sentuhan tipis: keluaran TTP223 berkedip (HIGH/LOW 50–400 ms) | `btnraw` untuk melihat level mentah. Sentuh dengan bantalan jari rata; jangan menambal di firmware (celah sama dengan jeda double tap) |

Perintah diagnostik console: `info`, `scan`, `oled`, `i2c <kHz>`, `ble`, `help`. Bring-up hardware: `tone`, `sweep`, `adc`, `btnraw`.
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
- **v0.5.4 ✅** Pengingat ketinggalan dua arah (2026-11-17). Firmware: SETTINGS `0x09 leave_alert` (NVS `leave`),
  alasan putus BLE dari `setCustomGapHandler` + RSSI tiap 2 dtk (`link_ble::takeLoss`), keputusan di `link.cpp`
  (alasan `0x208`, RSSI < −70, 20 dtk), modul tersembunyi **Tertinggal** (`left_module`, GOTO boleh), console `left`.
  Aplikasi 0.5.4: `LeaveAlert.kt` (status GATT 8 + RSSI ≥ −70 = dekat → notifikasi saja; wake lock; Matikan/Jeda 1 jam),
  `Alarm.startLeave/stopLeave`, halaman `leave_page.dart`; perbaikan: sambung ulang saat Bluetooth HP menyala lagi.
  Lulus 152/152 uji USB, 33 uji Flutter. Diuji di HP lewat adb: Lokana ditahan di bootloader → status 8, RSSI −58
  → notifikasi "Lokana terputus" tanpa bunyi, hilang saat tersambung lagi; Bluetooth HP dimatikan → Lokana: alasan
  `0x213` → tanpa pengingat. Uji berjalan menjauh (dua arah) oleh Wayan: berfungsi.
- **Urutan kerja (keputusan Wayan 2026-11-17): Android dulu sampai selesai, baru iPhone.**
  0. ✅ **Pasang ikon baru** (2026-11-17; `res/values/colors.xml` `lokana_pink` + `splash_background`, notifikasi
     `setColor` pink, latar launch & splash Flutter `#1A161E`): salin `brand/android/res/*` → `app/android/app/src/main/res/` (timpa ikon
     Flutter bawaan dan `ic_stat_lokana.xml` lama), tambah `android:roundIcon="@mipmap/ic_launcher_round"` di
     `<application>`. Cek pemanggil `R.drawable.ic_stat_lokana` di Kotlin tetap jalan. Build, uninstall, pasang,
     lalu cek ikon di launcher, themed icon (Android 13+), dan status bar. Detail: `brand/README.md`.
     Aksen "Lokana" di `theme.dart` sudah diganti pink `#F478AA` (toska lama jadi pilihan "Toska", "Merah muda"
     dihapus karena kembar). Cari sisa warna toska `0xFF2BB3C0`/`#2BB3C0` di Kotlin (warna notifikasi
     `setColor`) dan `res/` (launch_background, styles) lalu samakan ke pink; latar splash pakai `#1A161E`.
  1. ✅ **Desain ulang aplikasi Android** (2026-11-17, diuji Wayan di HP) sesuai `docs/DESIGN.md` (mockup di artifact "Lokana App — desain"),
     bisa jalan paralel selama Lokana Cube belum dirakit. Kerjakan per layar, jangan sekaligus; uji di HP tiap layar.
     Progres (`DESIGN.md` §7): ✅ 1 token & tema (`lib/tokens.dart`, `context.lk`; pink brand hanya lewat
     `AppTheme.primaryButton` karena tema FilledButton ikut berlaku untuk tonal), ✅ 2 `lib/cube.dart` `LokanaCube`
     + `paintLokanaEyes` (pratinjau: Pengaturan → Tentang → Lokana Cube), ✅ 3 `lib/shell.dart` 4 tab (halaman lama
     dengan `embedded: true`; Cari HP masih di Pengaturan sampai langkah 6), ✅ 4 Beranda (hero `LokanaCube` + chip
     Tersambung/sinyal RSSI dari `BleLink.lastRssi()`/baterai hanya jika persen asli, `QuickAction` 88 dp, Remote
     Tap/2×/Tahan, kisi `StudioTile` dengan thumbnail OLED asli → `ShellNav.go(Tabs.studio, segment:)`; berhasil =
     haptic ringan + mood senang), ✅ 5 Studio (`OledPreview` glow + grid piksel saat ≥ 2,5 dp/piksel + label
     `label: true`; `SlotGrid` 4×2 di `ui.dart`: cuplikan teks font piksel ukuran 2 / thumbnail galeri, kosong =
     garis putus-putus, memuat = kerangka; Teks & Gambar: "Kirim ke" = Tampilkan sekarang / Simpan ke slot + pilih
     slot dari grid), ✅ 6 Terhubung (segmen Ketinggalan · Notifikasi · Cari HP; `lib/radar.dart` `LeaveRadar`: dua cincin,
     jarak = `(−rssi − 50) / 40`, dekat 2,8 dtk rapat, jauh 1,2 dtk lebar, null = diam & redup, Cube melirik saat jauh;
     `pages/find_phone_page.dart` berisi cara memanggil + nada yang dipindah dari Pengaturan).
     ✅ 7 Pengaturan (kartu perangkat dengan `LokanaCube` + status; Lokana: kecerahan, layar mati, suara, putar 180°,
     Panduan, nama BT lewat lembar bawah; kerangka abu-abu saat REPORT dibaca; Aplikasi; Lainnya: Cara pakai, pratinjau
     Cube, lisensi, versi), ✅ 8 Sambungkan (hero `LokanaCube`: mengantuk saat diam/menyambung ulang, melirik saat
     mencari, siaga saat menyambung/pairing; satu aksi utama "Sambungkan ke <nama>" atau "Cari Lokana"; kartu
     perangkat dengan Cube kecil + bar sinyal; kerangka saat mencari), ✅ 9 Poles (`sendReaction`: haptic + `CubeCheer`
     di semua kirim; Ekspresi tanpa emoji lewat `lib/face_preview.dart` = port geometri `face.cpp`, dicek berdampingan
     dengan tangkapan firmware; `SkeletonCard` ganti spinner; `OledPreview` diam saat "kurangi animasi"; mode terang
     + huruf 130% tanpa overflow, Ukuran huruf Teks jadi chip). Semua langkah `DESIGN.md` §7 selesai dan disetujui Wayan.
  2. Lanjut **Backlog hasil audit** di bawah (v0.5.5 Daya, OTA, Play Store, CI, Desktop, kerapian), lalu v0.6 dst.
  - 🟡 **Slot teks: kelola dari Lokana** (ide Wayan). Slot 1–8 + `TEXT_SLOT` **sudah ada sejak v0.5.3**,
    jangan dibuat ulang. Sisanya: cek modul Teks di Lokana, lalu tambah yang belum ada: pilih/putar slot,
    hapus, atur lama tampil, putar bergiliran otomatis (semua dengan satu tombol sentuh), dan beberapa slot
    contoh bawaan untuk unit baru. Menulis teks tetap dari aplikasi.
  - 🟡 **Menu Developer pin** (setelah desain baru + OTA): menu tersembunyi (Pengaturan → Tentang → ketuk Versi 7×).
    Pin SDA/SCL/tombol (aktif HIGH/LOW)/buzzer/baterai ADC/deteksi charge + slot fitur baru; pin pindah dari
    compile-time ke NVS; pesan baru `HW_CONFIG`; firmware memvalidasi ulang; mode uji auto-kembali 60 dtk kalau
    OLED tidak terdeteksi/tidak dikonfirmasi; console `pins reset`. Peringatan: ⛔ GPIO18/19 (USB) dan pin
    bentrok; ⚠️ strapping GPIO2/8/9 (aman untuk I2C ber-pull-up, bukan untuk tombol yang menarik LOW saat boot;
    GPIO9 = tombol BOOT, GPIO8 = LED onboard); ℹ️ GPIO20/21 = UART0 (log boot); baterai/charge wajib ADC1 GPIO0–4.
- **Fase iPhone (JANGAN dikerjakan sebelum Android selesai dan Wayan bilang mulai):** pengguna iPhone 11 sudah
  menunggu. Tidak ada Mac, jadi pilih jalur tanpa Xcode lokal.
  1. **Mode iPhone tanpa aplikasi (ANCS + CTS)** (firmware): firmware jadi GATT *client* di koneksi yang sama
     (iPhone = central). Iklankan *solicitation* ANCS (`7905F431-B5CE-4E99-A40F-4B1E122D00D0`), bonding lewat
     Settings → Bluetooth iPhone (passkey di OLED, sama dengan alur sekarang). Isi:
     - ANCS: notifikasi (judul + aplikasi + isi pendek) → modul Notifikasi; panggilan masuk (kategori IncomingCall)
       → modul Panggilan; *Positive/Negative Action* untuk terima/tolak bila didukung.
     - CTS (`0x1805`): sinkron jam otomatis saat tersambung.
     - Pengingat ketinggalan tetap jalan dari sisi Lokana (RSSI). Cari HP tidak tersedia tanpa aplikasi.
     - **Sambung ulang** ke iPhone dikenal rewel: iklan cepat sebentar setelah putus, simpan bond, *keep-alive*,
       uji di iPhone 11 sungguhan (kunci layar, Bluetooth mati-nyala, jauh-dekat, semalaman).
     - Aplikasi Android dan Lokana Link tidak boleh rusak: deteksi jenis HP dari ada/tidaknya layanan ANCS.
     - Rujukan: proyek IlluminANCS (ESP32-C3 + NimBLE). Tulis ringkasan di `docs/ARCHITECTURE.md`.
  2. **Lokana Web: aplikasi yang sama untuk iPhone tanpa Mac** (⏳ *usulan, tunggu OK Wayan*, karena
     menyentuh keputusan "konfigurasi hanya lewat aplikasi"; ini bukan web portal di perangkat).
     Build **Flutter Web** dari kode `app/` yang sama, dihosting di GitHub Pages, memakai **Web Bluetooth**.
     iPhone membukanya lewat browser gratis **Bluefy** (Safari belum mendukung Web Bluetooth). Chrome di
     Android/PC juga bisa, jadi sekaligus jadi pengganti Desktop sederhana.
     - Mulai dengan **spike**: satu halaman HTML/JS kecil → konek, pairing passkey (karakteristik terenkripsi),
       kirim 1 frame, terima ACK di Bluefy + iPhone 11. Kalau gagal, berhenti dan laporkan.
     - Abstraksi `LinkBackend`: `ChannelBackend` (Android, MethodChannel ke Kotlin, perilaku sekarang) dan
       `WebBleBackend` (pakai `dart:js_interop`, **tanpa paket pihak ketiga**). Framing/`seq`/ACK/potong per MTU
       diport dari `BleLink.kt` ke Dart khusus web, dan diuji byte-nya di `test/`.
     - Halaman khusus Android (akses notifikasi, ketinggalan di HP, Cari HP, nada dering, baterai) disembunyikan
       di web. Notifikasi dan jam di iPhone datang lewat ANCS/CTS (poin 1).
     - Pengaturan disimpan di `localStorage` (web), bukan SharedPreferences.
  3. **Aplikasi iOS native (kalau pembeli iPhone bertambah)**: build lewat GitHub Actions runner
     macOS (gratis untuk repo publik): `flutter build ios --release --no-codesign` → .ipa. Untuk uji, pasang dengan
     Sideloadly di Windows memakai Apple ID gratis (kedaluwarsa 7 hari). Untuk pembeli, perlu Apple Developer
     Program (berbayar tahunan) → TestFlight/App Store. Lapisan BLE iOS ditulis Swift (CoreBluetooth). Ikon:
     `brand/ios/AppIcon.appiconset/`.
- **Backlog hasil audit 2026-11-17 (urut prioritas; setelah tugas 0–1 di atas kecuali Wayan bilang lain):**
  - 🔴 **v0.5.5 Daya & baterai** (pengukuran arus menunggu Lokana Cube dirakit)
    1. Ukur arus (USB tester / multimeter seri baterai): layar nyala, layar mati, BLE terhubung vs iklan. Catat di
       `docs/ARCHITECTURE.md` §2.5 + perkiraan umur baterai 700 mAh.
    2. Manajemen daya: `esp_pm_configure` (DFS 80–160 MHz + `light_sleep_enable`, butuh `CONFIG_PM_ENABLE` — cek
       apakah Arduino 2.0.17 prebuilt mendukung; kalau tidak, kurangi CPU ke 80 MHz + `delay()` di loop saat layar
       mati), interval koneksi BLE lebih panjang saat layar mati (`updateConnParams`), interval iklan lebih jarang
       setelah 1 menit tanpa koneksi. Jangan sampai merusak pengingat ketinggalan (RSSI tiap 2 dtk).
    3. Baterai: aktifkan `-DPIN_BATT=1` di env `supermini` (wokwi sudah), ikon baterai di status bar/Info, kirim
       persen asli di `DEVICE_INFO`, peringatan < 3.55 V, layar mati paksa + deep sleep < 3.40 V (ingat drop D1),
       opsional GPIO4 deteksi charge (ADC > 2.1 V) → ikon mengisi.
  - ✅ (lihat v0.5.5 di atas) **OTA + rollback** (sebelum ada unit dijual): `OTA` sesuai spesifikasi (BEGIN/CHUNK/END/ABORT/PROGRESS,
    SHA-256), hanya BLE terenkripsi/USB; timpa `verifyRollbackLater()` lalu `esp_ota_mark_app_valid_cancel_rollback()`
    setelah boot sehat (OLED + BLE siap); uji rollback dengan firmware yang sengaja crash. Aplikasi: halaman update
    (ambil rilis GitHub, tombol "Lihat perubahan & kode di GitHub"). Mode Update (WiFi AP / USB) masih menunggu keputusan Wayan.
  - 🟡 **Kesiapan Play Store**: kunci rilis (bukan debug key), kebijakan privasi, deklarasi akses notifikasi &
    `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`; pertimbangkan **CompanionDeviceManager** (izin latar + dialog pairing
    yang lebih baik — sekaligus menutup backlog dialog PIN generik).
  - ✅ **CI GitHub Actions** (2026-11-21, `.github/workflows/ci.yml`): firmware 3 env, `flutter analyze/test`, `selftest`.
  - ✅ **Rilis GitHub pertama v0.5.7** (2026-11-21): aset `lokana-os-0.5.7.bin` (nama wajib `lokana-os-*.bin`, dibaca
    halaman Update aplikasi) + APK. Setiap rilis: naikkan `FW_VERSION` + `pubspec.yaml` + `CLIENT_NAME` (BleLink.kt),
    pindahkan `[Belum dirilis]` di CHANGELOG ke versi baru, build `pio run -e supermini` + APK, `gh release create`.
  - 🟡 **Lokana Desktop** masih 0% (`desktop/` kosong): mulai dari `protocol/tools/lokana_link.py` → monitor PC lewat USB (v0.7).
  - 🟢 **Kerapian repo**: ✅ `hardware/case/` di-commit (tanpa `_render/`), ✅ `CHANGELOG.md` (v0.3.0 → sekarang;
    perbarui setiap rilis), ✅ versi di `app/README.md`. Sisa: `web/` placeholder bertentangan dengan keputusan
    "tanpa web flasher" → jadikan quick start GitHub Pages (`docs/`) atau hapus; lisensi hardware (CERN-OHL) di
    `hardware/`, `CONTRIBUTING.md`, rilis GitHub (firmware .bin + APK); cek tampilan Wokwi (belum sejak v0.2).
- **v0.5.5 🧪 OTA + rollback** (2026-11-18, poin 2 permintaan Wayan): `services/ota` (BEGIN/CHUNK berurutan +
  kiriman ulang/END dengan SHA-256/ABORT/PROGRESS 64 KB, batas 30 dtk), `verifyRollbackLater()` = true, masa uji 10 dtk
  + loop watchdog, valid lewat `esp_ota_mark_app_valid_cancel_rollback()`, NVS `ota/try` untuk pesan rollback,
  penanda `LOKANA_OS_VERSION:` di image, modul tersembunyi **Update** (bar progres), console `ota`, env
  `supermini-otacrash`. Aplikasi 0.5.5: `update_page.dart` (GitHub Releases `lokana-os-<versi>.bin` / file .bin),
  `LokanaLink.sendFirmware`, Kotlin `sha256`/`pickFile`/`openUrl`/`keepScreenOn`/`LeaveAlert.quietFor`, izin INTERNET.
  Lulus 175/175 uji USB (termasuk `test_v055`), uji OTA USB: update sukses + firmware rusak rollback.
  **OTA lewat BLE dari HP lulus 2026-11-21** (unit 1, aplikasi 0.5.6): 1,18 MB ±90 dtk, firmware sehat ditandai valid,
  `0.5.6-rusak` rollback otomatis. Belum diuji: macet di loop (watchdog) di hardware.
- **Lokana Cube unit 1 — bring-up ✅** (2026-11-21, COM10): I2C 0x3C, OLED (frame ±25 ms), TTP223 (tap/2×/3×/tahan
  dengan bantalan jari), buzzer (terkeras ±1300 Hz → nada Cari kunci 1300/1500 Hz), deteksi charge GPIO4 (2,8 V dicolok,
  ±15 mV dicabut), pembagi baterai 2,10 (multimeter). Penyimpangan wiring unit 1: `hardware/BOM.md`. Berikutnya: poin 2
  kode baterai v0.5.6, poin 3 uji daya USB tester, poin 4 OTA BLE dari HP (lihat permintaan Wayan 2026-11-21).
- **v0.5.6 🧪 Baterai** (2026-11-21, poin 2 permintaan Wayan): `PIN_BATT=1` + `PIN_CHG=4` di env `supermini`,
  kalibrasi pembagi per unit (`batt cal`, NVS), persen asli + `battery_mv` + bit mengisi/lemah di `DEVICE_INFO`
  (dikirim ulang saat berubah), ikon baterai OLED (Jam + lencana pojok), peringatan < 3,55 V, deep sleep < 3,40 V
  (`services/power`), chip baterai di aplikasi 0.5.6 (Beranda + Pengaturan). Diuji di unit 1: kalibrasi 2,082,
  deteksi charge, chip aplikasi, 178/178 uji USB. Belum diuji: peringatan < 3,55 V dan deep sleep (butuh sel hampir habis).
- **Ukur arus ✅** (2026-11-21, poin 3): layar nyala/mati × BLE tersambung/iklan = 45/30/40/28 mA, mengisi 0,38 A (TP4056
  hangat tipis, Rprog 2,7k tetap). Umur ±20 jam pemakaian biasa. Tabel & kesimpulan: `docs/ARCHITECTURE.md` §2.5.
  Manajemen daya (light sleep, CPU, interval BLE) **sekarang boleh dikerjakan**, ukur ulang tabel setelah tiap langkah.
- **v0.5.7 ✅ Manajemen daya tahap 1** (2026-11-21, bertahap, tiap langkah diukur USB tester + didokumentasikan di
  `docs/ARCHITECTURE.md` §2.5 — permintaan Wayan: **setiap perubahan didokumentasikan**). Arduino 2.0.17 prebuilt tanpa
  `CONFIG_PM_ENABLE` → tidak ada light sleep otomatis. ✅ 1 CPU 80 MHz (`CPU_MHZ`): 45/30/40/28 → 46/22/39/27 mA.
  ✅ 2 BLE (`link_ble.cpp`, `link_ble::setActive` dari `link.cpp`): iklan hemat 1 dtk setelah 60 dtk, koneksi 125 ms +
  latency 3 saat layar mati → 45/21/35/22 mA (pemakaian biasa ±23 mA → ±27 jam). **Dihentikan di sini atas
  keputusan Wayan.** Dicek di HP setelah langkah 2: Cari kunci, notifikasi, dan sambung ulang saat layar mati normal.
  Backlog daya (belum dikerjakan):
  - Langkah 3 OLED/I2C: kirim frame hanya jika isi berubah / frame rate lebih rendah saat diam (layar nyala ±24 mA
    untuk OLED + I2C; frame tiap 30 ms, kirim ±25 ms). Ukur kecerahan Redup vs Terang.
  - Hardware: LED daya merah Super Mini (selalu menyala) dan LED biru GPIO8 (ikut SCL) bisa dilepas resistornya.
  - Light sleep sungguhan (perkiraan ±3–6 mA saat layar mati, beberapa hari per isi): framework dengan
    `CONFIG_PM_ENABLE` + `CONFIG_BT_CTRL_MODEM_SLEEP` (mis. Arduino-ESP32 3.x lewat pioarduino `custom_sdkconfig`),
    migrasi NimBLE-Arduino 2.x. Proyek terpisah, perlu OK Wayan.
- **v0.7 ✅ Lokana Desktop / Monitor PC — dirilis v0.7.0 (2026-11-25).** Keputusan Wayan: **Python + system tray** (lanjut dari
  `lokana_link.py`, psutil, `.exe` PyInstaller), layar **menyala terus + geser piksel** selama data masuk, metrik
  CPU/RAM %, suhu CPU/GPU (LibreHardwareMonitor), jaringan & disk, baterai laptop + jam. Langkah:
  - ✅ 1 Firmware (2026-11-25): `services/stats_store` + `modules/monitor_module` (4 metrik/halaman, bar, halaman 5 dtk,
    tap = berikutnya, geser 1 px tiap 2 menit, `keepAwake` selama data, 10 dtk tanpa data → kembali), `PC_STATS`
    bit caps 2, `lokana_link.py pcstats`, `test_v07`. Ikut diperbaiki: Tertinggal langsung tertutup (unsigned) dan
    event saat layar mati hilang (lihat tabel jebakan). 202/202 uji USB.
  - ✅ 2 Lokana Desktop 0.7.0 (2026-11-25, `desktop/`, lihat `desktop/README.md`): venv `desktop/.venv` (psutil, pyserial,
    pystray, pillow, pyinstaller; **jangan** pasang ke Python sistem), `build.bat` → `dist\LokanaDesktop.exe` (14,6 MB).
    Diuji di laptop Wayan (Ryzen 5 7535HS, RTX 2050): tersambung COM10 ±1 dtk, CPU/RAM, GPU 48 °C (nvidia-smi),
    jaringan/disk, baterai `Batre+`; suhu CPU AMD butuh LibreHardwareMonitor (belum terpasang → baris dilewati, **belum
    diuji**). Jebakan: `.exe` --noconsole → `sys.stdout` None (jangan `print` tanpa cek); `.exe` onefile = 2 proses
    (matikan paksa → sisa proses memegang COM; keluar lewat tray bersih).
  - ✅ 3 Dokumentasi & rilis 0.7.0 (2026-11-25): `desktop/README.md` (pasang, pakai, LibreHardwareMonitor untuk suhu
    CPU AMD, tabel masalah umum), README/ARCHITECTURE (v0.6 & v0.7 selesai; monitor HP & timer/pomodoro pindah ke v0.9),
    CHANGELOG [0.7.0], `build.bat` melapor GAGAL bila `.exe` lama masih berjalan. Saat uji rilis ketemu & diperbaiki:
    Panduan/splash/jam memakai selisih waktu unsigned (lihat tabel jebakan). 203/203 uji USB. **Uji OTA 0.6.0 → 0.7.0
    lulus** (2026-11-25): unit 1 di-flash 0.6.0 resmi dari GitHub, aplikasi 0.7.0 → cek pembaruan → 0.7.0 dari GitHub
    Releases lewat BLE ±103 dtk → boot, ditandai valid.
- **v0.6 ✅ Navigasi Google Maps — dirilis v0.6.0 (2026-11-25)** di GitHub Releases. NAV (ikon panah dari notifikasi
  Maps → bitmap 1-bit), modul Navigasi. **OTA dari GitHub Releases terbukti** (2026-11-25): aplikasi 0.6.0 → cek
  pembaruan → unduh `lokana-os-0.6.0.bin` → BLE → unit 1 naik ke 0.6.0 dan ditandai sehat (uji Wayan).
  Dikerjakan **bersama** dua permintaan Wayan (2026-11-21). Keputusan Wayan: layar navigasi **menyala saat belokan**
  (instruksi baru / < 300 m, lalu ikut batas waktu), "mode developer" = **toast + label DEV + Info**, "charging" =
  **teks di lencana**. Langkah (satu commit per langkah, uji di unit 1, tunggu OK Wayan):
  - ✅ 1 Penanda (2026-11-21): `usb::host()` (`HWCDC::isPlugged()`, hanya komputer), toast "mode developer" (stabil
    1 dtk, tidak saat boot), label DEV kiri atas, "DEV" di Info; toast + lencana "charging", Jam bergantian
    "charging 78%". Diuji Wayan di unit 1.
  - 🟡 2 Contoh notifikasi Google Maps asli (2026-11-24, Infinix Android 16, Maps bahasa Indonesia): format
    **ProgressStyle** (*promoted ongoing*, kategori `navigation`): `android.title` = "Ambil arah menuju Jl. Raya Anturan"
    (instruksi + jalan), `android.subText` = "Tiba 01.02" (jam tiba), `android.text` kosong, `android.progressMax` =
    panjang rute (m), `android.progress`, `android.shortCriticalText` (kosong saat diam), `largeIcon` 94×94 panah biru,
    `smallIcon` 132×132 panah putih + alpha. Jarak ke belokan saat bergerak **belum terlihat** (HP diam).
    Perekam: `NavCapture.kt` (aktif hanya jika ada file `ON`):
    `adb shell touch /sdcard/Android/data/io.github.taicicaks01.lokana/files/nav_capture/ON` (Git Bash: `MSYS_NO_PATHCONV=1`),
    ambil `adb pull /sdcard/Android/data/io.github.taicicaks01.lokana/files/nav_capture`. Sisa: rekam perjalanan sungguhan.
  - ✅ 3 Firmware NAV (2026-11-24): `services/nav_store` (data RAM; event `EV_NAV` hanya mulai/belokan baru/≤ 300 m/
    selesai, karena setiap event menyalakan layar & mereset batas waktu), `modules/nav_module` (`available()` baru di
    `Module`: dilewati giliran & GOTO saat tidak aktif; `keepAwake` ≤ 300 m; `drawsBattery` = layar penuh),
    kedaluwarsa 3 menit / HP putus, field opsional `eta_text`, console `nav`, `lokana_link.py nav`, `test_v06`.
    191/191 uji USB; skenario layar (mulai → mati saat jauh → menyala di 280 m → belokan baru → selesai) dicek Wayan.
    Label DEV dibatasi ke layar wajah (menutupi judul Notif).
  - ✅ 4 Aplikasi, parser (2026-11-24/25): `NavForwarder.kt` (dipanggil `NotifListener` sebelum filter
    aplikasi; saklar "Navigasi Google Maps" di halaman Notifikasi, `NotifPrefs.nav`, bawaan nyala). Data asli saat
    bergerak: title "2,9 km · Belok kiri ke Jl. Damai/Jl. I Gede Taman", `shortCriticalText` "2,9 km",
    subText "Tiba 01.39"; spasi angka–satuan = **NBSP** (dinormalkan dulu). Kalimat dipecah di kata penghubung
    (menuju/ke/di/pada/onto…) → instruksi + jalan. Ikon: `smallIcon` jika bitmap (panah putih + alpha), selain itu
    `largeIcon`; skala 32×32 → 1-bit dari alpha. Kirim saat isi berubah (seq 0) + ulang tiap 20 dtk; notifikasi hilang
    → state 1. Diuji ujung ke ujung di unit 1 (layar: panah kiri, "2,9 km", "Belok kiri", jalan berjalan, "Tiba 01.43").
    **Uji perjalanan sungguhan oleh Wayan 2026-11-25: navigasi berjalan baik.** Dari rekaman 246 pembaruan:
    tepat di belokan Maps menghapus jarak ("50 m · Belok kiri ke X" → "Belok kiri ke X") → kalimat sama + jarak hilang
    setelah ≤ 300 m dikirim **0 m "Sekarang"**; transisi "Memulai navigasi…" / "Mengubah rute…" (elipsis, tanpa jam tiba,
    ikon 66×66) **tidak dikirim**; tiba = title "Tiba" + text "di <tujuan>" → jalan = nama tujuan; kaki terakhir =
    "5,1 km · <nama tujuan>"; notifikasi dihapus saat sampai/berhenti → state 1. Ikon lain: putar balik, tujuan
    (jalan + pin), semua putih + alpha. Saat diam di awal, Maps bisa bolak-balik dua instruksi (GPS) → **diredam sejak 0.7** (`nav_store`: belokan = belokan
    sebelum-terakhir dalam 60 dtk → tanpa event; uji console A,B,A,B,C → 1,2,0,0,2). Catatan lama:
    Lokana menyala/berbunyi tiap ganti; belum diredam. Perekam dimatikan (file `ON` dihapus) setelah data diambil.

## Cara berkomunikasi dengan pemilik proyek

- Gunakan **Bahasa Indonesia**. Saat memakai istilah teknis Indonesia, sertakan istilah
  Inggrisnya, contoh: tata letak (*layout*), pembaruan firmware (*firmware update*).
- Jelaskan hasil uji yang perlu dilihat langsung di hardware (apa yang harus tampil di OLED).
- Minta konfirmasi sebelum mengubah keputusan di bagian "Keputusan yang sudah final".
