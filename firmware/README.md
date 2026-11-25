# Lokana OS — firmware

Firmware untuk Lokana (ESP32-C3 Super Mini + OLED 0.96" 128×64). Versi **0.5.0**: sistem modul
dengan modul **Lokana** (wajah), **Jam**, **Notif**, **Dadu**, **Teks**, dan **Gambar**, layar
**Panggilan masuk**, plus **Lokana Link** lewat USB dan BLE (pairing passkey 6 digit di OLED)
untuk aplikasi Lokana.

Arsitektur lengkap: [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md)

## Menjalankan

### Simulasi (Wokwi)
1. Buka folder `firmware/` di VS Code / Antigravity (PlatformIO + Wokwi).
2. Build env **wokwi**, lalu `F1 → Wokwi: Start Simulator`.
3. OLED di Wokwi juga 128×64, sama dengan hardware asli.

### Hardware asli
1. Pilih env **supermini** (status bar atau Project Tasks), lalu **Upload**.
   Varian OLED 0.91" 128×32: env **supermini-091**.
2. Kalau port tidak muncul: tahan **BOOT**, tekan **RST**, lepas BOOT, lalu upload ulang.
3. Setelah upload, tekan **RST** sekali.

### Lewat terminal (PowerShell)

Jalankan dari folder `firmware/`. Kalau perintah `pio` tidak dikenal, ganti `pio` dengan
`C:\Users\<nama>\.platformio\penv\Scripts\platformio.exe`.

```powershell
cd lokana\firmware
pio device list                                   # lihat port board (VID:PID 303A:1001 = ESP32-C3)
pio run -e supermini                              # build saja
pio run -e supermini -t upload                    # build + upload (port dipilih otomatis)
pio run -e supermini -t upload --upload-port COM9 # pilih port sendiri kalau ada beberapa board
pio device monitor -b 115200                      # serial monitor, keluar: Ctrl+C
```

- **Selalu tulis `-e supermini`** (atau `-e supermini-091` untuk OLED 0.91"). Tanpa `-e`,
  PlatformIO memakai env default.
- **Tutup serial monitor sebelum upload.** Monitor memegang port, dan upload akan gagal
  ("could not open port").
- Setelah membuka monitor, tekan **RST** untuk melihat log boot, lalu ketik `help`.

### Pin

| Komponen | Pin |
|---|---|
| OLED 0.96" 128×64 (SSD1306) | SDA GPIO9, SCL GPIO8 (sejak 2026-11-21; Wokwi tetap 8/9) |
| Tombol | Sensor sentuh TTP223 di GPIO3 (VCC 3V3, GND, I/O → GPIO3). Tombol mekanis ke GND: tambah `-DBTN_ACTIVE_LOW=1` |
| Buzzer pasif (opsional) | GPIO10 |
| Baterai (ADC) | GPIO1, pembagi 100k/100k dari sisi saklar (`-DPIN_BATT=1` di env `supermini`) |
| Deteksi charge (ADC) | GPIO4, IN+ TP4056 → 100k → GPIO4 → 100k → GND (`-DPIN_CHG=4`) |
| LED bawaan | GPIO8 = SCL, tidak dipakai firmware |

## Penanda di layar

| Penanda | Kapan | Tampilan |
|---|---|---|
| **mode developer** | USB Super Mini tersambung ke komputer (host mengirim SOF, `usb::host()`); charger biasa tidak dihitung | Toast "mode developer" 2 dtk saat tersambung (stabil 1 dtk; tidak saat boot), label **DEV** di pojok kiri atas layar wajah, "DEV" di baris versi layar Info |
| **charging** | Charger TP4056 (USB bawah) dicolok, `battery::charging()` | Toast "charging" + nada saat dicolok; lencana "charging" + ikon mengisi di pojok kanan atas; di Jam baris tanggal bergantian tiap 3 dtk dengan "charging 78%" |
| Baterai lemah | Sel < 3,55 V | Toast "Baterai lemah" + nada, ikon berkedip |

## Cara pakai (satu tombol)

| Gestur | Fungsi |
|---|---|
| Tap | Aksi modul: colek Lokana · tampilkan detik · notifikasi berikutnya · bunyikan/hentikan HP · lempar dadu · ganti slot teks/gambar |
| Double-tap | Pindah modul (Lokana → Jam → Notif → Cari HP → Dadu → Teks → Gambar) |
| Triple-tap | Menu: kecerahan, suara, layar mati, putar layar, **Panduan**, lupakan HP, info |
| Tahan | Dadu: ganti jenis dadu. Notif: hapus notifikasi yang tampil. Modul lain: layar mati |

Di menu, tap = item berikutnya dan tahan = pilih/ubah. **Panduan** (0.5.3) membuka sub-menu: *Putar sekarang*,
*Saat boot* (On/Off, SETTINGS `boot_guide`), *Kembali*; double-tap di sub-menu = kembali ke menu.

**Panduan cara pakai** (`modules/guide_module`, tersembunyi): 6 kartu (Hai → TAP → 2x TAP → 3x TAP → TAHAN →
aplikasi), tiap gestur diperagakan jari di sensor sentuh, ±17 detik. Diputar 1,8 detik setelah splash boot
(`core::goToLater`, batal jika Lokana disentuh dulu), dari menu, atau `GOTO "Panduan"`. Sentuhan apa pun = lewati.

**Pengingat ketinggalan** (0.5.4, `modules/left_module`, SETTINGS `leave_alert`): koneksi BLE aman yang putus
karena *supervision timeout* (alasan `0x208`, dibaca lewat `NimBLEDevice::setCustomGapHandler`) dengan RSSI terakhir
< −70 dBm, dan HP tidak kembali dalam 20 detik → layar "HP-mu tertinggal?" + bunyi 30 detik (tap = diam). Keputusan
di `services/link.cpp`; log serial `[link] HP hilang: alasan …, RSSI … -> …`. Uji tampilan: console `left` / `left 0`.

Modul **Cari HP** (sejak 0.5.2 modul biasa, bukan
item menu): tap membuat HP yang tersambung berbunyi walau senyap, tap lagi untuk berhenti. Nadanya
dipilih di aplikasi (Pengaturan → Cari HP).

Modul **Teks** punya 5 font (CUSTOM_TEXT `font`): piksel bawaan, Sans, Sans Tebal, Serif, Mono Tebal
(font GFX Adafruit 9/12/18 pt). Teks yang lebih panjang dari layar mulai dari atas lalu bergulir.
Lama popup notifikasi diatur dari aplikasi (SETTINGS `notif_popup`, bawaan 6 detik, 0 = tidak muncul).

Nama Bluetooth bawaan **`Lokana_लोचन-01`** (`BLE_NAME_DEFAULT` di `config.h`), bisa diganti dari
aplikasi (Pengaturan) atau console `name`. Di OLED huruf Dewanagari tampil sebagai Latin (`locana`).

Modul **Gambar** adalah galeri slot 1–8 (gambar diam & animasi bingkai, littlefs `/img/N.bin`);
tap = slot berikutnya, label "Slot N" muncul sebentar.

Notifikasi baru muncul 6 detik (10 detik jika penting) lalu kembali ke modul sebelumnya; tap
menutupnya. Maks 8 notifikasi disimpan di RAM saja. Panggilan masuk menampilkan nama penelepon
dengan dering; tap membisukan dering Lokana (panggilan di HP tidak ditolak).

## Perintah serial (115200)

```
help  list  go dadu  expr senang  roll  roll d20  time 14:30
text Halo|dunia  img  find 5  find stop  phone  ble  forget
notif WhatsApp|Ibu|Sudah makan?  notif clear  call Ibu  call stop  name  name Lokana_saya  name -
tap  double  triple  long  info  scan  oled  reset  splash  splash 1300
```

Bring-up hardware (alat uji, sebagian *blocking*): `tone <Hz> [ms]`, `sweep [a] [b] [langkah] [ms]` (frekuensi tampil
di OLED, untuk mencari nada terkeras buzzer), `adc` (mV mentah GPIO1 baterai & GPIO4 charge + status kalibrasi),
`btnraw [dtk]` (rekam level mentah pin sentuh beserta lamanya).

Baterai: `batt` (tegangan, persen, charger, lemah/kritis). Kalibrasi per unit: ukur tegangan sel dengan multimeter
(saklar ON), lalu `batt cal 4.12` → faktor pembagi disimpan di NVS. `batt cal reset` kembali ke bawaan 2,0.

`guide [ms]` memutar Panduan (ms = bekukan di waktu itu, untuk screenshot).

Navigasi (v0.6) tanpa HP: `nav 250 Belok kanan|Jl. Udayana` (meter, instruksi `|` jalan; panah bawaan), `nav stop`.

## Modul Monitor PC (v0.7, Mode Meja)

Data dari pesan `PC_STATS` (dikirim Lokana Desktop tiap ±2 dtk) disimpan di `services/stats_store`. Modul `Monitor`
(`modules/monitor_module`) hanya ikut giliran double-tap selama data masuk, setelah Navigasi.

- 4 metrik per halaman (128×64): label kiri, nilai kanan; persen & suhu dengan bar 0–100. Halaman berganti tiap
  5 dtk, **tap** = halaman berikutnya, titik penanda halaman di kanan bawah.
- Data pertama menyalakan layar dan membuka Monitor; selama data masuk layar **tetap menyala** (dapat daya USB),
  isi digeser 1 px tiap 2 menit supaya OLED tidak *burn-in*. **Tahan** = layar mati seperti biasa.
- 10 dtk tanpa data → kembali ke modul sebelumnya.
- **Sejak 0.8** (caps `STATS_LAYOUT`): host boleh mengirim teks nilai siap tampil (`61°C`, `1,25MB/s`), label sampai
  10 huruf, dan susunan baris: dua metrik sebaris (nilai kanan diratakan kanan, nilai kiri 6 px di sebelahnya; bar
  dibagi dua kalau keduanya persen/suhu, satu bar penuh kalau hanya satu). `°` (UTF-8 C2 B0) digambar dengan glyph
  derajat font classic, hanya di `PC_STATS`. Halaman dihitung per baris.
- Uji tanpa Desktop: `python lokana_link.py pcstats --seconds 20` (metrik contoh).

## Modul Visualizer audio (v0.8, Mode Meja)

Data dari pesan `AUDIO_BANDS` (dikirim Lokana Desktop ±25 fps selama PC memutar suara) disimpan di
`services/audio_store`. Modul `Visualizer` (`modules/viz_module`) hanya ikut giliran double-tap selama pesan masuk,
setelah Monitor.

- Pesan pertama membuka Visualizer dan menyalakan layar; layar tetap menyala selama aktif. **1,5 dtk** tanpa pesan →
  kembali ke modul sebelumnya (biasanya Monitor). Pindah modul dengan 2× tap tidak dipaksa kembali.
- Gaya **Batang** (dari bawah, titik puncak ditahan 300 ms lalu turun ±1,2 dtk) dan **Cermin** (dari garis tengah).
  **Tap** = ganti gaya; host bisa mengatur gaya lewat field `style` (berlaku saat mulai/berubah).
- 8–32 pita; lebar batang = `SCREEN_W / count` − 1 px, dipusatkan.
- Uji tanpa PC: console `viz [dtk] [cermin]`, atau `python lokana_link.py audio --seconds 15 [--style 1]`.

## Modul Navigasi (v0.6)

Data dari pesan `NAV` disimpan di `services/nav_store` (bukan event, supaya pembaruan jarak tidak menyalakan layar).
Modul `Navigasi` (`modules/nav_module`) hanya ikut giliran double-tap selama navigasi berjalan (`Module::available()`),
tepat setelah wajah.

| Kejadian | Layar |
|---|---|
| Navigasi mulai | Menyala, buka Navigasi (label nama modul) |
| Belokan baru (instruksi / jalan / ikon berubah) | Menyala, buka Navigasi, bunyi notifikasi |
| Jarak masuk ≤ 300 m | Menyala + bunyi, bilah mendekat; layar **tetap menyala** selama ≤ 300 m |
| Pembaruan jarak biasa | Tidak menyalakan layar (ikut batas waktu) |
| Selesai (`state 1`), HP terputus, atau 3 menit tanpa `NAV` | Toast, kembali ke modul sebelumnya |

Layar: panah 32×32 (dari HP, atau panah lurus bawaan), jarak besar, instruksi & jalan (teks panjang berjalan),
waktu tiba. Pairing, cari kunci, panggilan, dan update tidak ditimpa; Panduan dan Tertinggal boleh ditimpa.
`splash` memutar ulang splash boot; `splash <ms>` membekukannya di waktu itu (untuk screenshot lewat
Layar Lokana / `lokana_link.py screen --shot`). Bitmap लोचन dibuat ulang dengan
`python firmware/tools/gen_splash.py` (Pillow, font Baloo 2 dari `app/assets/fonts/`).
`python firmware/tools/gen_oled_fonts.py` menyalin font OLED (glcdfont + 12 font GFX modul Teks) ke
`app/lib/oled_fonts.dart` untuk pratinjau teks di aplikasi; jalankan ulang jika font modul Teks berubah.

## Env build

| Env | Layar | Catatan |
|---|---|---|
| `supermini` | 128×64 | Default, hardware asli |
| `supermini-091` | 128×32 | Varian 0.91", tata letak ringkas (`-DSCREEN_H=32`) |
| `wokwi` | 128×64 | Simulasi: pin sama, tombol mekanis aktif LOW |
| `supermini-otacrash` | 128×64 | **Hanya untuk uji rollback OTA**: versi `0.5.5-rusak` yang sengaja crash di `setup()`. Kirim lewat OTA, jangan upload USB |

Tabel partisi: [`partitions.csv`](partitions.csv) (2 slot OTA 1,75 MB, littlefs 384 KB, coredump 64 KB).

## Lokana Link

Port USB yang sama membawa console teks dan frame biner (`A5 5A … CRC`). BLE beriklan sebagai
`Lokana-XXXX`; HP baru harus pairing dengan kode 6 digit yang tampil di OLED.
Uji dari PC: [`protocol/tools/lokana_link.py`](../protocol/tools/lokana_link.py) (`python lokana_link.py test`).

### Pembaruan firmware (OTA, 0.5.5)

`services/ota` menerima firmware lewat pesan `OTA` (BLE terenkripsi atau USB), menulisnya ke slot cadangan
(`app0`/`app1`), memeriksa SHA-256 saat END, lalu restart. Firmware baru berjalan dalam **masa uji 10 detik**
(`verifyRollbackLater()` ditimpa, loop dipantau watchdog 5 dtk); setelah OLED menjawab dan loop berjalan sehat,
baru ditandai valid (`esp_ota_mark_app_valid_cancel_rollback`). Crash, macet, atau OLED hilang selama masa uji =
restart dan bootloader kembali ke versi lama; layar menampilkan "v… gagal, versi lama".

- Versi Lokana OS ditanam di image sebagai penanda `LOKANA_OS_VERSION:<versi>` (header `esp_app_desc_t` berisi versi
  ESP-IDF, bukan Lokana). Aplikasi & alat PC membaca penanda ini dari file `.bin`.
- Rilis GitHub: lampirkan `firmware.bin` env `supermini` dengan nama **`lokana-os-<versi>.bin`**; aplikasi mencarinya
  di rilis terbaru (Pengaturan → Pembaruan firmware).
- Dari PC: `python protocol/tools/lokana_link.py ota .pio/build/supermini/firmware.bin` (kirim lewat USB, tunggu
  restart, laporkan berhasil / rollback). Console `ota` = slot yang berjalan, status masa uji, versi yang ditolak.
- Upload USB (`pio run -t upload`) menulis ulang `otadata`, jadi selalu boot dari `app0` tanpa masa uji.

Gambar dari aplikasi (BITMAP) disimpan di partisi **littlefs** (`/bmp/1.bin` … `/bmp/8.bin`);
partisi baru diformat otomatis saat boot pertama. Teks slot 1–8 dan pengaturan ada di NVS.

## Struktur kode

```
src/
├── main.cpp            daftar modul & startup
├── drivers/            display, button, buzzer, hw (LED, baterai)
├── core/               core (modul, menu, toast, layar), face (mata Lokana),
│                       events, settings, clock
├── services/           console, link (Lokana Link: link_proto, link_usb, link_ble),
│                       text_store (NVS), image_store (littlefs, animasi), notif_store (RAM)
└── modules/            face_module, clock_module, notif_module (+ Panggilan), dice_module,
                        text_module, image_module,
                        system_modules (Pairing & Cari kunci: tersembunyi; Cari HP: modul biasa)
```

## Membuat modul baru

```cpp
// src/modules/halo_module.h
#include "config.h"
#include "core/module.h"
class HaloModule : public Module {
public:
  const char* name() const override { return "Halo"; }
  bool input(Gesture g) override { _n++; return g == G_TAP; }
  void render(Adafruit_GFX& g, uint32_t now) override {
    g.setTextSize(2); g.setCursor(10, SCREEN_H / 2 - 7); g.print("Halo "); g.print(_n);
  }
private:
  int _n = 0;
};
```

Lalu di `main.cpp`: `static HaloModule halo;` dan `core::addModule(&halo);`
