# Arsitektur Lokana

Dokumen ini menjelaskan cara sistem Lokana disusun: firmware di perangkat, protokol
komunikasi, aplikasi HP, dan Lokana Desktop. Baca ini sebelum mulai berkontribusi.

Ringkasan produk dan keputusan desain ada di [README](../README.md).
Spesifikasi protokol ada di [protocol/LOKANA_LINK.md](../protocol/LOKANA_LINK.md).

## 1. Gambaran besar

```
┌────────────────────────┐                     ┌────────────────────────┐
│ Aplikasi Lokana (HP)   │                     │ Lokana Desktop (PC)    │
│ Flutter + Kotlin       │                     │ sensor PC dari         │
│ Android dulu, iOS nanti│                     │ LibreHardwareMonitor   │
└───────────┬────────────┘                     └───────────┬────────────┘
            │ BLE (terenkripsi, bonded)                    │ USB serial  /  WiFi UDP
            │                                              │
            └──────────────┐            ┌──────────────────┘
                           ▼            ▼
                  ┌──────────────────────────┐   LOKANA LINK:
                  │       LOKANA OS          │   satu format pesan
                  │       ESP32-C3           │   untuk semua jalur
                  └────────────┬─────────────┘
                               │ ESP-NOW (eksperimental)
                      ┌────────▼────────┐
                      │ Lokana teman    │
                      └─────────────────┘

GitHub: repo (kode) · Releases (firmware .bin) · Pages (quick start)
```

| Jalur | Dipakai oleh | Kapan aktif |
|---|---|---|
| **BLE** Lokana Link | Aplikasi HP | Selalu (Mode Saku & Meja) |
| **BLE HID** | Laptop/HP (presentasi, media, Win+L) | Mode Meja |
| **USB serial** Lokana Link + console | Lokana Desktop, skrip uji, developer | Saat dicolok ke PC |
| **WiFi UDP** Lokana Link | Lokana Desktop tanpa kabel data | Mode Meja, setelah WiFi diatur lewat aplikasi |
| **ESP-NOW** | Lokana lain | Eksperimental |

Tidak ada web portal maupun web flasher di perangkat. Semua konfigurasi lewat aplikasi HP.

## 2. Lokana OS (firmware)

Empat lapisan; setiap lapisan hanya memakai lapisan di bawahnya.

```
┌─────────────────────────────────────────────────────────────┐
│ 4. MODUL      src/modules/   Lokana (wajah), Jam, Dadu,     │
│                              Teks, Notif, Navigasi, Monitor │
├─────────────────────────────────────────────────────────────┤
│ 3. LAYANAN    src/services/  console (teks serial),         │
│                              link (parser Lokana Link),     │
│                              ble, usb, wifi, ota            │
├─────────────────────────────────────────────────────────────┤
│ 2. INTI       src/core/      core (modul, menu, toast,      │
│                              layar), face (mata), events,   │
│                              settings, clock                │
├─────────────────────────────────────────────────────────────┤
│ 1. DRIVER     src/drivers/   display, button, buzzer,       │
│                              hw (LED, baterai)              │
└─────────────────────────────────────────────────────────────┘
```

### 2.1 Sistem modul

Setiap fitur adalah sebuah **modul** (`src/core/module.h`):

```cpp
class Module {
public:
  virtual const char* name() const = 0;           // nama di menu & toast
  virtual void enter() {}                          // modul dibuka
  virtual void exit() {}                           // modul ditutup
  virtual bool input(Gesture g) { return false; }  // true = gestur ditangani modul
  virtual void event(const Event& e) {}            // kejadian dari sistem
  virtual void update(uint32_t now) {}             // logika, dipanggil tiap loop
  virtual void render(Adafruit_GFX& g, uint32_t now) = 0;  // gambar ke layar
  virtual bool keepAwake() const { return false; } // cegah layar mati otomatis
};
```

Menambah fitur = membuat satu file di `src/modules/`, lalu mendaftarkannya di `main.cpp`
dengan `core::addModule(&modulKamu)`. Inti firmware tidak perlu diubah.

**Ukuran layar:** modul menggambar memakai `SCREEN_W × SCREEN_H` dari `config.h`.
Target utama **128×64** (OLED 0.96"). Varian 128×32 (0.91") tetap bisa di-build, tetapi
tata letak dirancang untuk 128×64 dulu.

### 2.2 Aturan tombol (sama di semua modul)

| Gestur | Fungsi |
|---|---|
| Tap | Aksi utama modul (lempar dadu, colek Lokana, …) |
| Double-tap | Pindah ke modul berikutnya |
| Triple-tap | Buka menu |
| Tahan | Aksi kedua modul (misal ganti jenis dadu); jika modul tidak memakainya → layar mati |

### 2.3 Event bus

Kejadian dikirim lewat antrean `events::post()` dan diteruskan Core ke semua modul.
Layanan **link** menerjemahkan pesan Lokana Link menjadi event, jadi modul tidak perlu
tahu pesan datang dari BLE, USB, atau WiFi.

```
BLE / USB / UDP → link (parser) → events::post(EV_NOTIF, …) → Core → modul Notif
```

### 2.4 Layanan link

- Satu **parser aliran byte** untuk semua transport. BLE memberi byte mentah;
  USB dan UDP membuka envelope `A5 5A … CRC16` dulu.
- Pesan dari device ke host dikirim lewat transport asal pesan terakhir, atau ke semua
  transport yang tersambung untuk pesan spontan (`FIND_PHONE`, `DICE`, `BUTTON`).
- Console teks serial tetap bekerja di port USB yang sama dengan frame biner.

### 2.5 Daya

| Status | Layar | Radio | Kapan |
|---|---|---|---|
| Aktif | Nyala | BLE (+WiFi di Mode Meja) | Sedang dipakai |
| Layar mati | Mati | BLE tetap tersambung | Didiamkan melewati batas waktu |
| Tidur ringan (*light sleep*) | Mati | BLE hemat daya | Mode Saku |
| Tidur dalam (*deep sleep*) | Mati | Mati | Baterai hampir habis |

- **Mode Saku**: WiFi mati, BLE hemat daya. Tidak masuk *deep sleep* karena cari kunci
  dan pengingat ketinggalan butuh BLE tetap tersambung.
- **Mode Meja**: dideteksi dari daya USB; WiFi boleh hidup untuk monitor PC lewat UDP.

**Hasil ukur arus (2026-11-21, Lokana Cube unit 1, firmware 0.5.6, USB tester)**

Arus kerja diukur di USB kanan dari charger dinding, saklar OFF (Lokana hidup murni dari USB). Regulator 3,3 V
linier, jadi arus dari sel kurang lebih sama. Belum ada manajemen daya: CPU 160 MHz tanpa *light sleep*, interval BLE
bawaan NimBLE, OLED kecerahan bawaan.

| # | Layar | BLE | Arus | Umur baterai* |
|---|---|---|---|---|
| 1 | Nyala (wajah) | Tersambung | 45 mA | ±14 jam |
| 2 | Mati | Tersambung | 30 mA | ±21 jam |
| 3 | Nyala | Iklan (HP tidak tersambung) | 40 mA | ±16 jam |
| 4 | Mati | Iklan | 28 mA | ±22 jam |

\* LiPo 102530 ±700 mAh, terpakai ±630 mAh (4,20 → 3,40 V, batas deep sleep). Pemakaian Mode Saku biasa (layar
menyala ±10% waktu, HP tersambung) ≈ 0,1 × 45 + 0,9 × 30 ≈ **31 mA → ±20 jam**, jadi isi daya tiap hari.

Mengisi (USB bawah, saklar OFF, Rprog 2,7 kΩ): **0,38 A pada 5,08 V** saat sel 4,15 V (sudah dekat fase CV, jadi di
bawah 440 mA), TP4056 hanya hangat tipis → Rprog 2,7 kΩ dipertahankan. Perkiraan isi penuh dari kosong ±2 jam.

Kesimpulan: mematikan layar hanya menghemat ±15 mA; sisa ±28–30 mA adalah CPU yang terus berjalan + radio. Penghematan
besar ada di manajemen daya (*light sleep* otomatis, CPU 80 MHz saat diam, interval koneksi BLE lebih panjang saat layar
mati, iklan lebih jarang setelah 1 menit). Target berikutnya: ukur ulang tabel ini setelah tiap langkah.

**Manajemen daya (0.5.7, bertahap; ukur ulang tiap langkah dengan susunan yang sama)**

Arduino-ESP32 2.0.17 *prebuilt* dikompilasi tanpa `CONFIG_PM_ENABLE` dan tanpa *modem sleep* controller BLE
(`tools/sdk/esp32c3/sdkconfig`), jadi `esp_pm_configure` (DFS + *light sleep* otomatis) tidak tersedia. Yang bisa:
frekuensi CPU tetap, loop yang banyak menunggu (task idle menjalankan WFI), parameter BLE, dan beban OLED/I2C.
*Light sleep* sungguhan butuh framework yang dikompilasi ulang (ESP-IDF / Arduino 3 dengan sdkconfig sendiri).

| Langkah | Perubahan | Nyala + sambung | Mati + sambung | Nyala + iklan | Mati + iklan | Pemakaian biasa* |
|---|---|---|---|---|---|---|
| 0 | Awal (0.5.6, CPU 160 MHz) | 45 mA | 30 mA | 40 mA | 28 mA | ±31 mA → ±20 jam |
| 1 | CPU 80 MHz (`CPU_MHZ`, `setCpuFrequencyMhz` paling awal di `setup()`) | 46 mA | 22 mA | 39 mA | 27 mA | ±25 mA → ±25 jam |
| 2 | BLE: iklan hemat + interval koneksi panjang saat layar mati (`link_ble.cpp`) | 45 mA | 21 mA | 35 mA | 22 mA | ±23 mA → ±27 jam |

\* Layar nyala ±10% waktu, HP tersambung: 0,1 × kolom 1 + 0,9 × kolom 2; sel terpakai ±630 mAh.

Catatan langkah 1: 80 MHz adalah minimum untuk BLE di ESP32-C3; APB tetap 80 MHz sehingga I2C, UART, dan LEDC tidak
berubah. Layar nyala tidak turun: bebannya OLED + I2C (frame tiap 30 ms, kirim ±25 ms → bus sibuk ±80%, LED biru di
GPIO8/SCL ikut berkedip). Layar mati + iklan lebih boros dari tersambung → interval iklan bawaan terlalu rapat.
Uji USB 178/178 lulus di 80 MHz; animasi & sentuhan tetap responsif.

Catatan langkah 2 (Lokana meminta, HP yang memutuskan; HP uji Infinix menyetujui keduanya):
- Iklan (HP tidak tersambung): 100–150 ms selama layar menyala dan 60 dtk setelah boot/putus, lalu 1–1,1 dtk.
  Layar dinyalakan → kembali cepat (mungkin sedang mau menyambungkan HP). Sambung ulang dari mode hemat bisa
  beberapa detik lebih lambat.
- Koneksi: aktif (layar nyala, OTA, mirror layar) 15–30 ms latency 0 → HP memberi 22 ms; layar mati 100–150 ms
  latency 3 → 125 ms (Lokana bangun ±0,5 dtk saat tidak ada data). Supervision timeout 4 dtk untuk keduanya.
  Permintaan dikirim 3 dtk setelah koneksi aman. RSSI pengingat ketinggalan tetap tiap 2 dtk.
- Parameter yang dipakai HP tercatat di log (`[ble] koneksi: ...`) dan perintah `ble`.
- Iklan hemat paling terasa (mati + iklan −5 mA). Mati + tersambung hanya −1 mA: radio bukan beban utama lagi.
  Sisa ±21 mA = chip yang tidak pernah tidur (CPU 80 MHz tanpa *light sleep*, controller BLE tanpa *modem sleep*).
  Penurunan besar berikutnya hanya lewat framework dengan `CONFIG_PM_ENABLE` + `CONFIG_BT_CTRL_MODEM_SLEEP`.

Status (2026-11-21): manajemen daya **berhenti setelah langkah 2** (keputusan pemilik). Peluang yang tersisa, belum
dikerjakan: (3) OLED/I2C — kirim frame hanya jika berubah / frame rate rendah saat diam, untuk beban layar nyala ±24 mA;
hardware — lepas LED daya merah & LED biru GPIO8 Super Mini; light sleep sungguhan lewat framework yang dikompilasi
ulang (perkiraan ±3–6 mA saat layar mati).

**Baterai (sejak 0.5.6, `drivers/hw.cpp` + `services/power.cpp`)**
- Sel dibaca tiap 1 dtk lewat GPIO1 (pembagi dari sisi saklar, sebelum D1), rata-rata 16 sampel + EMA. Di bawah
  2,5 V = sel tidak terbaca (saklar OFF, hanya USB kanan) → persen `255` di `DEVICE_INFO`.
- Faktor pembagi per unit dikalibrasi lewat console `batt cal <volt multimeter>` (NVS `batt/div`), bawaan 2,0.
- Persen dari kurva LiPo 3,40 V = 0% … 4,20 V = 100%. Saat mengisi, tegangan naik ±0,1 V sehingga persen sedikit lebih tinggi.
- Charger dideteksi lewat GPIO4 (ADC > 2,0 V dicolok, < 1,5 V dicabut): toast "Mengisi daya", ikon mengisi.
- **< 3,55 V**: toast "Baterai lemah" + nada (diulang tiap 10 menit selama layar menyala), ikon berkedip.
- **< 3,40 V selama 10 bacaan** (tanpa charger, tanpa USB komputer, tidak sedang OTA): layar "Baterai habis", lalu
  *deep sleep*. Bangun lewat sensor sentuh; saat boot sel diperiksa lagi (ambang 3,45 V). Batas ini menjaga regulator
  3,3 V yang mulai kurang tegangan sekitar 3,5 V karena drop D1, dan sel tetap di atas proteksi DW01 (±2,4 V).
- Ikon: Jam (128×64) di ujung bilah detik; modul lain hanya lencana pojok kanan atas saat lemah/mengisi.
- `DEVICE_INFO` dikirim ulang tanpa diminta saat status daya berubah (protokol §DEVICE_INFO).

### 2.6 Memori (flash 4 MB)

Partisi custom (`firmware/partitions.csv`, sejak v0.2; dipasang lewat `board_build.partitions`):

| Partisi | Offset | Ukuran | Isi |
|---|---|---|---|
| nvs | `0x9000` | 20 KB | Pengaturan, kunci pairing BLE, WiFi |
| otadata | `0xE000` | 8 KB | Penanda slot aktif |
| app0 | `0x10000` | 1,75 MB | Firmware slot A |
| app1 | `0x1D0000` | 1,75 MB | Firmware slot B (OTA) |
| littlefs | `0x390000` | 384 KB | Teks & bitmap tersimpan, aset |
| coredump | `0x3F0000` | 64 KB | Catatan crash untuk debugging |

Firmware v0.2 berukuran ~790 KB (43% slot app), jadi masih ada ruang untuk BLE (NimBLE), WiFi, dan modul baru.

Catatan:
- `nvs` tetap di `0x9000` (sama dengan tabel bawaan), jadi pengaturan lama tidak hilang saat pindah ke tabel ini.
- `littlefs` memakai subtype `spiffs` (standar PlatformIO) dengan label `littlefs`. Saat dipasang nanti:
  `LittleFS.begin(false, "/littlefs", 10, "littlefs")` (label bawaan Arduino adalah `"spiffs"`).
- `coredump` memakai format ELF (bawaan sdkconfig Arduino-ESP32). Pesan boot
  `esp_core_dump_flash: Incorrect size` di v0.1 muncul karena partisi ini belum ada.

### 2.7 Pembaruan firmware

Tiga jalur, satu sumber (**GitHub Releases**):

| Jalur | Mekanisme | Versi |
|---|---|---|
| Build dari kode | `pio run -e supermini -t upload` lewat USB | ✅ sekarang |
| Mode Update | Mekanisme masih didiskusikan (WiFi AP + unggah lewat browser HP, atau USB) | v0.8 |
| OTA lewat aplikasi | Pesan `OTA` Lokana Link lewat BLE (atau USB dari PC) | ✅ v0.5.5 |

Firmware baru ditulis ke slot cadangan. Setelah boot sukses, firmware menandai dirinya
valid; kalau gagal, bootloader kembali ke slot lama (*rollback*).

**Hasil cek rollback (v0.2, Arduino-ESP32 2.0.17 / `espressif32@6.9.0`):**

- Bootloader bawaan ESP32-C3 **sudah** dikompilasi dengan `CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE=y`
  (`tools/sdk/esp32c3/sdkconfig` di paket framework). Tidak perlu bootloader custom.
  *Anti-rollback* (`CONFIG_BOOTLOADER_APP_ANTI_ROLLBACK`) tidak aktif, dan memang tidak dibutuhkan.
- **Jebakan:** `initArduino()` (`cores/esp32/esp32-hal-misc.c`) langsung memanggil
  `esp_ota_mark_app_valid_cancel_rollback()` **sebelum `setup()`**, karena fungsi weak
  `verifyOta()` bawaan selalu `true`. Akibatnya firmware baru yang crash di `setup()` atau
  `loop()` tetap dianggap valid; rollback hanya terjadi kalau crash sebelum `setup()`.
- **Sudah diterapkan (v0.5.5, `firmware/src/services/ota.cpp`):** `verifyRollbackLater()` ditimpa (return
  `true`); `ota::bootCheck()` di `setup()` mendeteksi status *pending verify*, menolak langsung jika OLED tidak
  menjawab, dan memasang loop task ke watchdog (5 dtk, panic). `ota::update()` menandai valid setelah 10 dtk sehat.
  Versi yang sedang dicoba disimpan di NVS (`ota/try`) supaya setelah rollback firmware lama bisa melapor versi yang
  gagal. Penulisan memakai `OTA_WITH_SEQUENTIAL_WRITES` (hapus flash per sektor, tidak memblokir lama).
- **Diuji 2026-11-18 di Super Mini (USB, `lokana_link.py ota`):** 0.5.5 → 0.5.5-ota berhasil (88 dtk untuk 1,1 MB,
  ±13 KB/dtk; `app1` valid); 0.5.5-ota → 0.5.5-rusak (crash di `setup()`) kembali sendiri ke 0.5.5-ota. SHA-256
  salah, image rusak, data bukan firmware, CHUNK salah urutan, ABORT, dan batas waktu 30 dtk ditolak tanpa mengubah
  firmware (`test_v055`). Macet di loop (watchdog) belum diuji di hardware.
- Upload lewat USB (`pio run -t upload`) menulis ulang `otadata` kosong, jadi status
  *pending verify* tidak berlaku untuk jalur "build dari kode".

## 3. Lokana Link (protokol)

Ringkasan; detail lengkap di [protocol/LOKANA_LINK.md](../protocol/LOKANA_LINK.md).

```
frame:     [type u8][seq u8][len u16 LE][payload]
USB / UDP: A5 5A [frame] [CRC-16/CCITT-FALSE u16 LE]
BLE:       frame mentah lewat characteristic RX (write) / TX (notify)
```

| Rentang | Kelompok | Contoh |
|---|---|---|
| `0x00–0x05` | Sistem | `HELLO`, `TIME_SYNC`, `DEVICE_INFO`, `SETTINGS`, `OTA`, `ACK` |
| `0x10–0x15` | Informasi | `NOTIF`, `NAV`, `PC_STATS`, `MEETING`, `PHONE_STATS`, `CALL` |
| `0x20–0x25` | Aksi | `FIND_KEYS`, `FIND_PHONE`, `EXPRESSION`, `DICE`, `GOTO`, `BUTTON` |
| `0x30–0x31` | Tampilan | `CUSTOM_TEXT`, `BITMAP` |
| `0x40–0x41` | Jaringan | `WIFI_PROV`, `WIFI_STATUS` |

## 4. Aplikasi Lokana (HP)

| Bagian | Teknologi | Tanggung jawab |
|---|---|---|
| UI | Flutter | Layar sambung/pairing, pengaturan, teks & emoji, ekspresi, dadu, cari kunci |
| BLE + framing | Kotlin (`BleLink.kt`, tanpa plugin) | Scan, connect, bonding, MTU, antrean tulis, `seq`/ACK/kirim ulang |
| Layanan latar | Kotlin (*foreground service*) | Menjaga koneksi BLE saat aplikasi ditutup; Cari HP berbunyi walau layar mati |
| Notifikasi & navigasi | Kotlin (*NotificationListenerService*) | Membaca notifikasi terpilih dan notifikasi navigasi Google Maps |
| Codec payload | Dart (`lib/link/proto.dart`) | Encode/decode payload sesuai spesifikasi; diuji dengan byte asli firmware |

BLE ditulis langsung di Kotlin, bukan `flutter_blue_plus`: sejak 2.x plugin itu memakai lisensi
sendiri (berbayar untuk perusahaan ≥ 15 orang) dan mengirim nama paket ke server pembuatnya
setiap build. Koneksi di Kotlin juga memudahkan v0.5: *NotificationListener* bisa mengirim pesan
lewat `BleLink` tanpa menunggu UI Flutter hidup.

**Android dulu:** semua fitur wajib berjalan di Android sebelum iOS dikerjakan.
**iOS nanti:** notifikasi lewat ANCS langsung dari iPhone (butuh bonding, sudah disiapkan),
navigasi memakai rute sendiri karena aplikasi lain tidak bisa dibaca.

## 5. Lokana Desktop

| Tahap | Bentuk | Isi |
|---|---|---|
| v0.3 | Skrip Python (`protocol/tools/`) | Penguji protokol lewat USB: `HELLO`, `TIME_SYNC`, teks, ekspresi |
| v0.7 | Lokana Desktop awal | Monitor PC lewat USB, status rapat |
| v0.8 | Lokana Desktop + WiFi | Monitor PC lewat UDP, mDNS untuk menemukan Lokana |

Data sensor diambil dari **LibreHardwareMonitor** (suhu, kipas, GPU, daya) dan `psutil`
(CPU, RAM, disk, jaringan). Browser tidak bisa membaca sensor hardware, jadi aplikasi PC
tetap dibutuhkan.

**v0.7 (2026-11-25, `desktop/`)**: Python + system tray (`pystray`), dibungkus PyInstaller jadi satu
`LokanaDesktop.exe`. Kode protokol dipakai ulang dari `protocol/tools/lokana_link.py`; koneksi sendiri
(`link_usb.py`): cari port VID 303A, `HELLO` (client_type 3) → hanya yang membalas `DEVICE_INFO`
device_type 1, port lain dilewati 5 menit, buka tanpa DTR/RTS, sambung ulang otomatis. `TIME_SYNC` saat
tersambung + tiap jam, `PC_STATS` tiap 2 dtk tanpa ACK. Sensor (`sensors.py`): psutil (CPU/RAM/jaringan/
disk/baterai), `nvidia-smi` (suhu & pemakaian GPU NVIDIA), LibreHardwareMonitor lewat web server lokal
`127.0.0.1:8085/data.json` (suhu CPU, opsional). Di Lokana: modul Monitor (§ firmware README).

## 6. Struktur repo

```
lokana/
├── CLAUDE.md       konteks proyek untuk asisten AI (Claude Code)
├── README.md       ringkasan produk, fitur, roadmap, keputusan desain
├── firmware/       Lokana OS (PlatformIO)
├── protocol/       spesifikasi Lokana Link + skrip uji
├── app/            aplikasi Lokana (Flutter + Kotlin)
├── desktop/        Lokana Desktop
├── hardware/       skema, PCB, casing 3D
└── docs/           arsitektur, quick start (GitHub Pages)
```

## 7. Urutan pengerjaan

| Versi | Fokus | Hasil |
|---|---|---|
| v0.1 ✅ | Fondasi | Driver, core, sistem modul, Lokana/Jam/Dadu, console, diagnostik I2C |
| v0.2 ✅ | Layar 128×64 + partisi | Tata letak 128×64, `partitions.csv`, cek rollback |
| v0.3 ✅ | Lokana Link | Parser, transport USB + BLE, pairing passkey, skrip uji Python, modul Teks |
| v0.4 ✅ | Aplikasi MVP | Sambung, pengaturan, teks/emoji, ekspresi, dadu, cari kunci ↔ HP |
| v0.5 ✅ | Notifikasi | NotificationListener, panggilan, modul Notif |
| v0.6 | Navigasi | Panah + jarak + jalan dari Google Maps, modul Navigasi |
| v0.7 | Mode Meja | Lokana Desktop via USB, monitor HP, timer & pomodoro |
| v0.8 | Jaringan | WiFi provisioning, UDP, Mode Update |
| v0.9 | Integrasi | BLE HID, OTA lewat aplikasi, cuaca, musik |
| v1.0 | Siap jual | Hemat daya, casing, kemasan, quick start |
