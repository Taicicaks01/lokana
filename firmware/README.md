# Lokana OS — firmware

Firmware untuk Lokana (ESP32-C3 Super Mini + OLED 0.96" 128×64). Versi **0.4.0**: sistem modul
dengan modul **Lokana** (wajah), **Jam**, **Dadu**, **Teks**, dan **Gambar**, plus **Lokana Link**
lewat USB dan BLE (pairing passkey 6 digit di OLED) untuk aplikasi Lokana.

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
| OLED 0.96" 128×64 (SSD1306) | SDA GPIO8, SCL GPIO9 |
| Tombol | Sensor sentuh TTP223 di GPIO3 (VCC 3V3, GND, I/O → GPIO3). Tombol mekanis ke GND: tambah `-DBTN_ACTIVE_LOW=1` |
| Buzzer pasif (opsional) | GPIO10 |
| LED bawaan | GPIO8 = SDA, tidak dipakai firmware |

## Cara pakai (satu tombol)

| Gestur | Fungsi |
|---|---|
| Tap | Aksi modul: colek Lokana · tampilkan detik · lempar dadu · ganti slot teks/gambar |
| Double-tap | Pindah modul (Lokana → Jam → Dadu → Teks → Gambar) |
| Triple-tap | Menu: **Cari HP**, kecerahan, suara, layar mati, putar layar, lupakan HP, info |
| Tahan | Dadu: ganti jenis dadu. Modul lain: layar mati |

Di menu, tap = item berikutnya dan tahan = pilih/ubah. **Cari HP** (item pertama: triple-tap lalu
tahan) membuat HP yang tersambung berbunyi walau senyap; tap di Lokana untuk berhenti.

## Perintah serial (115200)

```
help  list  go dadu  expr senang  roll  roll d20  time 14:30
text Halo|dunia  img  find 5  find stop  phone  ble  forget
tap  double  triple  long  info  scan  oled  reset
```

## Env build

| Env | Layar | Catatan |
|---|---|---|
| `supermini` | 128×64 | Default, hardware asli |
| `supermini-091` | 128×32 | Varian 0.91", tata letak ringkas (`-DSCREEN_H=32`) |
| `wokwi` | 128×64 | Simulasi: pin sama, tombol mekanis aktif LOW |

Tabel partisi: [`partitions.csv`](partitions.csv) (2 slot OTA 1,75 MB, littlefs 384 KB, coredump 64 KB).

## Lokana Link

Port USB yang sama membawa console teks dan frame biner (`A5 5A … CRC`). BLE beriklan sebagai
`Lokana-XXXX`; HP baru harus pairing dengan kode 6 digit yang tampil di OLED.
Uji dari PC: [`protocol/tools/lokana_link.py`](../protocol/tools/lokana_link.py) (`python lokana_link.py test`).

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
│                       text_store (NVS), bitmap_store (littlefs)
└── modules/            face_module, clock_module, dice_module, text_module, image_module,
                        system_modules (Pairing, Cari kunci, Cari HP: tersembunyi)
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
