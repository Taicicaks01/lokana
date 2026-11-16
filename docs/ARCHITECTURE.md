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
| OTA lewat aplikasi | Pesan `OTA` Lokana Link lewat BLE | v0.9 |

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
- **Rencana untuk OTA (v0.8/v0.9):** di `main.cpp` timpa fungsi weak
  `bool verifyRollbackLater() { return true; }` supaya Arduino tidak menandai valid otomatis,
  lalu panggil `esp_ota_mark_app_valid_cancel_rollback()` sendiri setelah boot terbukti sehat
  (misalnya `setup()` selesai, OLED menjawab, dan loop berjalan ±10 detik tanpa crash).
  Kalau firmware reset sebelum itu, bootloader otomatis kembali ke slot lama.
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
| BLE | `flutter_blue_plus` | Scan, connect, bonding, MTU, kirim/terima Lokana Link |
| Layanan latar | Kotlin (*foreground service*) | Menjaga koneksi BLE saat aplikasi ditutup |
| Notifikasi & navigasi | Kotlin (*NotificationListenerService*) | Membaca notifikasi terpilih dan notifikasi navigasi Google Maps |
| Codec protokol | Dart (bersama untuk semua layar) | Encode/decode frame sesuai spesifikasi |

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
| v0.4 | Aplikasi MVP | Sambung, pengaturan, teks/emoji, ekspresi, dadu, cari kunci ↔ HP |
| v0.5 | Notifikasi | NotificationListener, panggilan, modul Notif |
| v0.6 | Navigasi | Panah + jarak + jalan dari Google Maps, modul Navigasi |
| v0.7 | Mode Meja | Lokana Desktop via USB, monitor HP, timer & pomodoro |
| v0.8 | Jaringan | WiFi provisioning, UDP, Mode Update |
| v0.9 | Integrasi | BLE HID, OTA lewat aplikasi, cuaca, musik |
| v1.0 | Siap jual | Hemat daya, casing, kemasan, quick start |
