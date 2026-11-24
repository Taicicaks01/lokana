<div align="center">

# Lokana

**Lokana — melihat untukmu.**

Robot mini open source berbasis ESP32-C3 yang menemani di saku sebagai gantungan kunci
dan di meja sebagai asisten kerja. Lokana memantau HP, kunci, dan komputermu,
lalu memberi kabar lewat sepasang matanya.

![Status](https://img.shields.io/badge/status-pengembangan%20awal-orange)
![Versi](https://img.shields.io/badge/Lokana%20OS-v0.7.0-blue) ![CI](https://github.com/Taicicaks01/lokana/actions/workflows/ci.yml/badge.svg)
![Platform](https://img.shields.io/badge/MCU-ESP32--C3-red)
![Layar](https://img.shields.io/badge/OLED-128%C3%9764-lightgrey)
![Lisensi kode](https://img.shields.io/badge/kode-MIT-green)
![Lisensi hardware](https://img.shields.io/badge/hardware-CERN--OHL-green)

<img src="docs/img/splash.gif" width="384" alt="Splash boot Lokana: tulisan Sansekerta लोचन (locana, mata)">

*Splash boot: लोचन (locana, "mata") turun dari garis atas yang lalu menjadi mata Lokana.*

[Fitur](#3-fitur) · [Arsitektur](#4-arsitektur-sistem) · [Mulai cepat](#7-mulai-cepat-untuk-developer) ·
[Roadmap](#9-roadmap) · [Kontribusi](#12-kontribusi)

</div>

---

> **Status proyek:** Lokana Cube pertama sudah dirakit dan diuji. **Lokana OS v0.7.0** menambahkan **Monitor PC**
> (Mode Meja) bersama aplikasi Windows **Lokana Desktop**, di atas v0.6.0: **navigasi Google Maps** (panah belokan + jarak,
> layar menyala saat mendekati belokan), dan v0.5.7: **baterai** (persen asli, peringatan,
> *deep sleep*), **pembaruan firmware lewat aplikasi (OTA + rollback)**,
> dan **hemat daya** (perkiraan ±27 jam pemakaian biasa, uji tahan baterai berjalan), di atas **notifikasi HP**, **panggilan masuk**, splash boot **लोचन**,
> **Panduan cara pakai**, **pengingat ketinggalan** dua arah,
> pengaturan, dadu, teks (5 font), gambar/emoji, dan Cari HP lewat **Lokana Link** (USB & BLE). **Aplikasi Lokana**
> (Android) sudah jalan di HP, dengan pratinjau teks yang sama persis dengan layar Lokana.
> **Lokana Desktop** (Windows, ikon tray) mengirim kondisi PC ke Lokana lewat USB (`desktop/`).
> Dokumen ini adalah acuan utama proyek: apa yang dibangun, keputusan yang sudah diambil, dan urutan pengerjaannya.

## Daftar isi

1. [Tentang Lokana](#1-tentang-lokana)
2. [Dua mode, satu karakter](#2-dua-mode-satu-karakter)
3. [Fitur](#3-fitur)
4. [Arsitektur sistem](#4-arsitektur-sistem)
5. [Lokana Link (protokol)](#5-lokana-link-protokol)
6. [Hardware](#6-hardware)
7. [Mulai cepat untuk developer](#7-mulai-cepat-untuk-developer)
8. [Pembaruan firmware](#8-pembaruan-firmware)
9. [Roadmap](#9-roadmap)
10. [Keputusan desain](#10-keputusan-desain)
11. [Batasan yang diketahui](#11-batasan-yang-diketahui)
12. [Kontribusi](#12-kontribusi)
13. [Lisensi & merek](#13-lisensi--merek)

---

## 1. Tentang Lokana

**Lokana** berasal dari bahasa Sanskerta ***locana*** (लोचन), artinya **mata,
penglihatan, "yang melihat"**. Nama ini dipilih karena:

- **Maknanya sama dengan fungsinya.** Lokana *melihat untukmu*: notifikasi HP, posisi
  kunci, kondisi komputer, lalu melaporkannya.
- **Wajahnya memang mata.** Karakter Lokana berupa sepasang mata animasi di layar OLED.
- **Berakar budaya, terdengar internasional.** Dekat dengan bahasa Kawi, Bali, dan Jawa,
  tetap mudah diucapkan orang luar.
- **Satu nama untuk semuanya.** Robotnya Lokana, alatnya Lokana, aplikasinya Lokana,
  firmware-nya **Lokana OS**, protokolnya **Lokana Link**.
- **Siap jadi ekosistem.** Gadget berikutnya memakai aplikasi dan protokol yang sama.

### Kenapa open source?

Lokana dijual sebagai produk **dan** dibuka kodenya. Tujuannya supaya pembeli penasaran
dengan cara kerjanya, mau membuka repo ini, belajar, lalu ikut mengembangkan.
Karena itu pembaruan firmware sengaja diarahkan ke repo ini (lihat
[Pembaruan firmware](#8-pembaruan-firmware)).

---

## 2. Dua mode, satu karakter

| Mode | Kapan | Daya | Koneksi aktif | Fungsi utama |
|---|---|---|---|---|
| **Mode Saku** (*pocket mode*) | Dibawa sebagai gantungan kunci | Baterai LiPo | **BLE ke HP saja**, WiFi mati | Notifikasi, navigasi, cari kunci, ekspresi |
| **Mode Meja** (*desk mode*) | Di samping laptop, dicolok USB / charger | USB | BLE ke HP + **USB atau WiFi ke PC** | Jam animasi, monitor PC & HP, presentasi, kontrol musik |

Aturannya sederhana: **di saku hemat daya, di meja semua koneksi boleh hidup.**

---

## 3. Fitur

Fitur dikelompokkan berdasarkan **dari mana datanya berasal**. Setiap fitur dibangun
sebagai **modul** terpisah di Lokana OS, jadi bisa ditambah atau dilepas tanpa mengganggu
fitur lain.

Keterangan status: ✅ sudah jalan · 🔨 sedang/berikutnya · 📋 direncanakan · 🧪 eksperimental / menunggu uji di HP

### 3.1 Lokana sendiri (tanpa HP)

| Fitur | Status | Penjelasan |
|---|---|---|
| Wajah & ekspresi | ✅ | 13 ekspresi (netral, senang, sedih, marah, ngantuk, kaget, cinta, pusing, curiga, bosan, semangat, gugup, kedip), berkedip dan melirik sendiri, bereaksi saat dicolek |
| Sistem mood | ✅ | Lama dicuekin → bosan → ngantuk; dicolek terus → curiga → marah |
| Jam animasi | ✅ | Digit besar dengan transisi geser, tanggal, detik |
| Dadu digital | ✅ | 1d6, 2d6, d4, d8, d10, d12, d20, koin; acak dari *hardware RNG* ESP32-C3 |
| Menu di perangkat | ✅ | Cari HP, kecerahan, suara, layar mati otomatis, putar layar, lupakan HP, info |
| Timer, stopwatch, pomodoro | 📋 | Untuk belajar, presentasi, dan fokus kerja |
| Mini game satu tombol | 📋 | Tes refleks, lompat rintangan |

### 3.2 Dari aplikasi HP (BLE)

| Fitur | Status | Penjelasan |
|---|---|---|
| Pairing aman | ✅ | Kode 6 digit tampil di OLED, diketik di dialog pairing Android; HP diingat (*bonding*) |
| Sinkron jam (*time sync*) | ✅ | Jam dan zona waktu otomatis dari HP |
| Teks & emoji custom | ✅ | Teks diam/berjalan/berkedip; emoji dirender HP menjadi bitmap 1-bit; 8 slot teks + 8 slot gambar |
| Ekspresi dari HP | ✅ | Ubah ekspresi Lokana dan lempar dadu dari aplikasi |
| Cari kunci ↔ cari HP | ✅ | Lokana berbunyi saat dicari; modul Cari HP di Lokana membuat HP berbunyi walau senyap |
| Pengingat ketinggalan | ✅ | Dua arah: HP berbunyi jika Lokana tertinggal, Lokana berbunyi jika HP tertinggal (sinyal melemah lalu putus; dimatikan di dekat HP = notifikasi saja) |
| Notifikasi HP | ✅ | Nama aplikasi + judul + potongan isi, dengan filter per aplikasi |
| Panggilan masuk | ✅ | Nama penelepon + bunyi |
| Navigasi Google Maps | ✅ | Panah belok, jarak, dan nama jalan (lihat [4.3](#43-cara-kerja-notifikasi--navigasi)). Layar menyala saat mendekati belokan; diuji di perjalanan sungguhan |
| Monitor HP | 📋 | Baterai, sinyal, dan memori HP di layar Lokana |
| Kontrol musik & cuaca | 📋 | Play/pause/next; cuaca dari aplikasi |
| Pengaturan WiFi (*BLE provisioning*) | 📋 | Nama & password WiFi dikirim dari aplikasi, tanpa web portal |
| Update firmware lewat aplikasi (OTA) | ✅ | Mengambil rilis terbaru dari GitHub Releases (atau file `.bin`), rollback otomatis |

### 3.3 Dari komputer (Lokana Desktop)

| Fitur | Status | Penjelasan |
|---|---|---|
| Monitor PC lewat USB | ✅ | CPU, RAM, suhu CPU/GPU, jaringan, disk, baterai laptop. **Lokana Desktop** (`desktop/`, ikon tray Windows) + layar Monitor di Lokana (0.7) |
| Monitor PC lewat WiFi | 📋 | Data dikirim lewat UDP dalam satu jaringan, tanpa kabel data |
| Status rapat | 📋 | Lokana menunjukkan "sedang rapat" saat mikrofon/kamera aktif |
| Remote presentasi & media keys | 📋 | Lokana menjadi keyboard Bluetooth (BLE HID): slide maju/mundur, volume |
| Kunci PC otomatis | 📋 | Kirim **Win+L** saat kamu menjauh dari laptop |

### 3.4 Eksperimental

| Fitur | Status | Catatan |
|---|---|---|
| Mode teman, pesan & dadu bersama | 🧪 | Antar-Lokana lewat **ESP-NOW**, tanpa router |
| Pemindai WiFi/BLE (edukasi) | 🧪 | Menghitung perangkat di sekitar dan kekuatan sinyal |
| Kode 2FA (TOTP) | 🧪 | Wajib *flash encryption*; bukan pengganti aplikasi autentikator |
| NetLab (WiFi repeater + whitelist situs) | 🧪 | Untuk belajar jaringan saja. Maks ~10 klien, lambat, mudah ditembus lewat data seluler/VPN/DoH, jadi **tidak cocok untuk pengamanan ujian** |

### 3.5 Butuh hardware tambahan (nanti)

| Fitur | Hardware |
|---|---|
| Remote IR universal (TV/AC/proyektor) | LED IR + penerima IR |
| Reaksi gerak (miring → melirik, goyang → pusing) | MPU6050 |
| Suhu & kelembapan ruangan | SHT31 / AHT20 |
| Suara karakter dan musik | Speaker I2S (MAX98357) |

---

## 4. Arsitektur sistem

### 4.1 Ekosistem

```
┌────────────────────────┐                     ┌────────────────────────┐
│   Aplikasi Lokana (HP) │                     │  Lokana Desktop (PC)   │
│  Flutter + Kotlin      │                     │  data sensor dari       │
│  Android dulu          │                     │  LibreHardwareMonitor  │
└───────────┬────────────┘                     └───────────┬────────────┘
            │ BLE (Lokana Link)                            │ USB serial / WiFi UDP
            │                                              │ (Lokana Link)
            ▼                                              ▼
        ┌──────────────────────────────────────────────────────┐
        │                 Lokana (ESP32-C3)                    │
        │                   Lokana OS                          │
        └──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│ GitHub: repo Lokana + Releases (firmware .bin) + Pages (quick start) │
└──────────────────────────────────────────────────────────────────────┘
```

| Komponen | Teknologi | Peran |
|---|---|---|
| **Lokana OS** | C++, PlatformIO, Arduino framework, NimBLE | Firmware di gadget |
| **Aplikasi Lokana** | Flutter (UI) + Kotlin (*NotificationListener*, *foreground service*) | Pusat kendali, pengaturan, notifikasi, navigasi, OTA |
| **Lokana Desktop** | Aplikasi PC (Windows dulu) | Mengirim data sensor PC lewat USB atau WiFi |
| **Lokana Link** | Protokol biner sederhana | Satu format pesan untuk BLE, USB, dan WiFi |
| **Quick start** | GitHub Pages (`docs/`) + kartu Canva ber-QR di kemasan | Panduan pembeli |

Satu aplikasi dipakai untuk **semua gadget Lokana** di masa depan. Aplikasi mengenali
jenis alat dari paket `DEVICE_INFO`.

**Tidak ada web portal di dalam alat.** Semua konfigurasi lewat aplikasi HP, termasuk
WiFi (*BLE provisioning*). Ini lebih aman dan menghemat flash/RAM.

### 4.2 Lapisan firmware (Lokana OS)

```
┌─────────────────────────────────────────────────────────────┐
│ modules/    Lokana (wajah) · Jam · Dadu · Teks · Notif · Nav │  fitur
├─────────────────────────────────────────────────────────────┤
│ services/   console (serial) · link (BLE/USB/WiFi) · ota     │  layanan
├─────────────────────────────────────────────────────────────┤
│ core/       core · face engine · events · settings · clock   │  inti
├─────────────────────────────────────────────────────────────┤
│ drivers/    display · button · buzzer · hw (LED, baterai)    │  hardware
└─────────────────────────────────────────────────────────────┘
```

- **Modul** adalah satu kelas turunan `Module` dengan `enter()`, `input()`, `event()`,
  `update()`, dan `render()`. Menambah fitur = membuat satu modul baru dan mendaftarkannya.
- **Event bus** meneruskan kejadian (pesan masuk, ganti ekspresi, lempar dadu, dll.) ke
  semua modul, jadi modul tidak saling bergantung.
- **Satu tombol, empat gestur:** tap = aksi modul, double-tap = modul berikutnya,
  triple-tap = menu, tahan = aksi kedua / layar mati.

Detail lengkap: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

### 4.3 Cara kerja notifikasi & navigasi

Saat navigasi Google Maps berjalan, Android menampilkan notifikasi yang terus diperbarui
(*ongoing notification*) berisi teks belokan, jarak, nama jalan, dan **ikon panah sebagai
bitmap**. Aplikasi Lokana membaca notifikasi itu lewat *NotificationListener*, mengecilkan
ikon panah menjadi bitmap 1-bit, lalu mengirimnya ke Lokana bersama jarak dan nama jalan.

Prinsip privasi: aplikasi hanya meneruskan **nama aplikasi, judul, dan potongan teks**
dari aplikasi yang dipilih pengguna. Isi lengkap tidak dikirim dan tidak disimpan.

---

## 5. Lokana Link (protokol)

Satu format pesan untuk semua jalur (BLE, USB serial, WiFi UDP):

```
frame:      [type u8][seq u8][len u16 LE][payload]
USB / UDP:  A5 5A [frame] [CRC-16 u16 LE]
BLE:        frame mentah lewat characteristic RX (write) / TX (notify)
```

`seq = 0` berarti tidak perlu balasan; `seq ≠ 0` wajib dibalas `ACK`.

| Rentang | Kelompok | Pesan |
|---|---|---|
| `0x00–0x05` | Sistem | `HELLO`, `TIME_SYNC`, `DEVICE_INFO`, `SETTINGS`, `OTA`, `ACK` |
| `0x10–0x15` | Informasi | `NOTIF`, `NAV`, `PC_STATS`, `MEETING`, `PHONE_STATS`, `CALL` |
| `0x20–0x25` | Aksi | `FIND_KEYS`, `FIND_PHONE`, `EXPRESSION`, `DICE`, `GOTO`, `BUTTON` |
| `0x30–0x31` | Tampilan | `CUSTOM_TEXT`, `BITMAP` |
| `0x40–0x41` | Jaringan | `WIFI_PROV`, `WIFI_STATUS` |

Koneksi BLE wajib terenkripsi dan *bonded*, dengan passkey 6 digit yang tampil di OLED.
Remote presentasi dan media keys memakai **BLE HID** standar, jadi laptop tidak butuh
aplikasi tambahan.

Spesifikasi lengkap (payload, keamanan, aturan kompatibilitas, contoh byte):
**[protocol/LOKANA_LINK.md](protocol/LOKANA_LINK.md)**.

---

## 6. Hardware

| Komponen | Keterangan | Pin |
|---|---|---|
| ESP32-C3 Super Mini | MCU RISC-V, WiFi + BLE 5, USB-C | — |
| **OLED 0.96" 128×64** (SSD1306, I2C) | Layar utama / wajah Lokana | SDA **GPIO9**, SCL **GPIO8** |
| Tombol | Sensor sentuh **TTP223** | GPIO3 |
| Buzzer pasif | Bunyi reaksi, notifikasi, cari kunci | GPIO10 |
| LED bawaan | Tidak dipakai (pinnya dipakai SCL) | GPIO8 |
| LiPo 3.7 V + TP4056 Type-C | Baterai & pengisian | Pembagi tegangan → GPIO1 |
| Dudukan meja (3D print) | Untuk Mode Meja | — |

> Layar **0.91" 128×32** tetap didukung lewat konfigurasi untuk versi gantungan kunci yang
> lebih kecil, tetapi tata letak utama dirancang untuk **128×64**.

> **Pelajaran dari prototipe:** kabel jumper murah bisa membuat OLED hanya menyala sekali
> lalu "hilang" dari bus I2C. Kalau `info` di serial menunjukkan waktu kirim frame ratusan
> milidetik atau `scan` tidak menemukan apa-apa, **ganti kabel dulu** sebelum menyalahkan
> layar atau kode.

---

## 7. Mulai cepat untuk developer

### Kebutuhan

- [VS Code](https://code.visualstudio.com/) / Antigravity + ekstensi **PlatformIO**
- Ekstensi **Wokwi** (opsional, untuk simulasi)
- Board ESP32-C3 Super Mini + OLED SSD1306

### Build & upload

```bash
git clone https://github.com/<akun>/lokana.git
cd lokana/firmware

# simulasi di Wokwi
pio run -e wokwi            # lalu F1 → "Wokwi: Start Simulator"

# hardware asli (OLED 0.96" 128×64)
pio run -e supermini -t upload
# varian OLED 0.91" 128×32
pio run -e supermini-091 -t upload
pio device monitor -b 115200
```

Kalau port tidak muncul: tahan **BOOT**, tekan **RST**, lepas BOOT, lalu upload ulang.
Setelah upload, tekan **RST** sekali.

### Perintah serial (115200 baud)

| Perintah | Fungsi |
|---|---|
| `help` · `list` · `info` | Bantuan, daftar modul, status perangkat |
| `go <modul>` · `expr <nama>` · `roll` | Buka modul, ubah ekspresi, lempar dadu |
| `time HH:MM` | Atur jam manual |
| `tap` · `double` · `triple` · `long` | Simulasi tombol |
| `scan` · `oled` · `i2c <kHz>` | Diagnostik I2C dan OLED |
| `reset` | Kembalikan pengaturan default |

### Struktur repo

```
lokana/
├── firmware/      Lokana OS (PlatformIO)
├── app/           Aplikasi Lokana (Flutter + Kotlin)
├── desktop/       Lokana Desktop (monitor PC)
├── protocol/      Spesifikasi Lokana Link + skrip uji
├── hardware/      Skema, PCB, casing 3D
└── docs/          Arsitektur & quick start (GitHub Pages)
```

Konteks proyek untuk asisten AI (Claude Code) ada di [`CLAUDE.md`](CLAUDE.md).

---

## 8. Pembaruan firmware

Semua firmware resmi dirilis di **GitHub Releases** repo ini, dengan *changelog* di setiap
rilis. Sengaja **tidak ada web flasher**: pembeli diarahkan ke repo supaya melihat kodenya.

| Jalur | Untuk | Cara | Status |
|---|---|---|---|
| **Mode Update** | Pembeli umum | Aktifkan Mode Update di Lokana, unduh `.bin` dari Releases, lalu pasang ke Lokana | 📋 mekanisme masih didiskusikan |
| **Build dari kode** | Yang ingin belajar | Clone repo → ubah → `pio run -t upload` | ✅ |
| **Update lewat aplikasi (OTA)** | Pembeli awam | Aplikasi mengambil rilis terbaru; tetap ada tombol "Lihat perubahan & kode di GitHub" | ✅ sejak 0.5.5 (uji BLE 0.5.6) |

Supaya pembaruan aman:

- Flash dibagi dua slot aplikasi (*OTA partitions*): firmware baru ditulis ke slot cadangan.
- Firmware baru yang gagal boot otomatis **kembali ke versi lama** (*rollback*).
- Jalur darurat lewat USB (tombol BOOT) selalu tersedia.

---

## 9. Roadmap

| Versi | Fokus | Isi | Status |
|---|---|---|---|
| **v0.1** | Fondasi | Driver, core, sistem modul, modul Lokana/Jam/Dadu, console serial, diagnostik I2C | ✅ selesai |
| **v0.2** | Layar 128×64 | Tata letak semua modul untuk 128×64, ekspresi lebih detail, partisi OTA | ✅ selesai |
| **v0.3** | BLE & Lokana Link | GATT service RX/TX, pairing kode 6 digit, `TIME_SYNC`, `DEVICE_INFO`, `FIND_KEYS`, modul Teks | ✅ selesai |
| **v0.4** | Aplikasi MVP | Flutter: sambungkan, pengaturan, teks/emoji custom, ekspresi, cari kunci ↔ cari HP | ✅ selesai |
| **v0.5** | Notifikasi | *NotificationListener*, filter aplikasi, panggilan masuk, modul Notif | ✅ |
| **v0.6** | Navigasi | Ikon panah + jarak + jalan dari Google Maps, modul Navigasi | ✅ rilis v0.6.0 |
| **v0.7** | Mode Meja | Lokana Desktop (Windows, tray) + modul Monitor PC lewat USB | ✅ rilis v0.7.0 (monitor HP & timer/pomodoro pindah ke versi berikutnya) |
| **v0.8** | Jaringan | Monitor PC via WiFi UDP, *BLE provisioning*, Mode Update | 📋 |
| **v0.9** | Integrasi | BLE HID (presentasi, media, Win+L), cuaca, musik, monitor HP, timer & pomodoro (OTA lewat aplikasi sudah ✅ sejak 0.5.5) | 📋 |
| **v1.0** | Siap jual | Hemat daya, casing, kemasan + kartu quick start, uji pasar | 📋 |

---

## 10. Keputusan desain

| Topik | Keputusan | Alasan |
|---|---|---|
| Aplikasi pihak ketiga | **Tidak memakai Chronos** | Kontrol penuh atas fitur, merek, dan protokol |
| Platform aplikasi | **Semua fitur wajib jalan di Android dulu**; iPhone tetap didukung, menyusul | Navigasi & notifikasi hanya bisa dibaca penuh di Android |
| Urutan pengerjaan | **Protokol → firmware → skrip uji PC → aplikasi Android → Lokana Desktop** | Aplikasi & desktop bergantung pada protokol dan firmware yang sudah stabil |
| Jalur update | **Ketiganya dibuat**: Mode Update, build dari kode, OTA lewat aplikasi | Pembeli umum, pelajar, dan pembeli awam sama-sama terlayani |
| Teknologi aplikasi | **Flutter + Kotlin** | UI satu kode; Kotlin untuk layanan latar & akses notifikasi |
| Layar | **OLED 0.96" 128×64** | Ruang cukup untuk navigasi, notifikasi, dan monitor PC |
| Koneksi HP | **BLE** | Hemat daya, cukup untuk semua fitur Mode Saku |
| Koneksi PC | **USB dulu**, WiFi UDP menyusul | USB tanpa setting jaringan; WiFi untuk meja tanpa kabel data |
| BLE ke PC | Tidak dipakai untuk data | BLE sudah dipakai HP; BLE di desktop Windows kurang stabil |
| Konfigurasi | **Hanya lewat aplikasi** | Tanpa web portal di alat: lebih aman, hemat memori |
| Web flasher | **Tidak ada** | Pembeli diarahkan ke repo GitHub supaya tertarik belajar |
| Quick start | **GitHub Pages** + kartu Canva ber-QR | Gratis, satu tempat dengan kode, ikut ter-update |
| Hardware tambahan | Ditunda | Versi pertama cukup board + OLED + tombol + buzzer |

### Pertanyaan terbuka

- Mekanisme **Mode Update**: Lokana membuka WiFi sendiri lalu `.bin` diunggah lewat browser
  HP, atau lewat USB ke laptop?
- Apakah versi gantungan kunci tetap memakai layar 0.91", atau semua varian memakai 0.96"?
- Kapan dukungan iPhone dikerjakan setelah fitur Android lengkap (notifikasi lewat ANCS,
  navigasi dengan rute sendiri)?

---

## 11. Batasan yang diketahui

- **ESP32-C3 hanya punya BLE**, tanpa Bluetooth klasik. Cukup untuk semua fitur di atas.
- **iPhone** tidak mengizinkan aplikasi membaca notifikasi aplikasi lain. Notifikasi harus
  lewat **ANCS** langsung dari iPhone, dan navigasi Google Maps tidak bisa dibaca.
- **Android** perlu izin *Notification Access*, izin Bluetooth (Android 12+), dan
  pengecualian penghemat baterai supaya koneksi tidak diputus.
- **Play Store** membatasi akses notifikasi; aplikasi harus dideklarasikan sebagai
  *companion device app*.
- **Monitor PC** butuh aplikasi di PC karena browser tidak bisa membaca sensor hardware.
- **Umur baterai** tergantung pemakaian layar dan BLE; angka pasti diukur di prototipe.
- **Penjualan resmi** perangkat WiFi/BLE di Indonesia wajib sertifikasi **SDPPI**.

---

## 12. Kontribusi

Kontribusi sangat diterima, terutama ekspresi baru, modul fitur, dan terjemahan.

1. *Fork* repo ini dan buat *branch* baru: `feat/nama-fitur`.
2. Untuk fitur baru, buat **modul** di `firmware/src/modules/` (contoh ada di
   [`firmware/README.md`](firmware/README.md)).
3. Pastikan `pio run -e supermini` dan `pio run -e wokwi` sama-sama berhasil.
4. Buka *pull request* dengan penjelasan singkat dan foto/video layar jika ada perubahan tampilan.

Gaya kode: C++ sederhana, tanpa `delay()` panjang di loop, perbandingan waktu memakai
`(int32_t)(now - t)` supaya aman dari *overflow* `millis()`.

---

## 13. Lisensi & merek

| Bagian | Lisensi |
|---|---|
| Kode (firmware, aplikasi, desktop) | [MIT](LICENSE) |
| Desain hardware (skema, PCB, casing) | CERN-OHL |
| Nama dan logo **Lokana** | Merek dagang pemilik proyek, tidak termasuk lisensi di atas |

Kamu bebas memakai, mengubah, dan menjual ulang kodenya sesuai lisensi MIT. Produk turunan
tidak boleh memakai nama atau logo Lokana tanpa izin.

---

<div align="center">

*Lokana — melihat untukmu.*

</div>
