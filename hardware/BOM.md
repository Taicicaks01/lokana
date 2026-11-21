# Lokana Cube v1.1: daftar komponen dan bahan (BOM)

Untuk satu unit Lokana Cube: ESP32-C3 Super Mini, OLED 0.96", baterai LiPo, dan casing 3D print.
Wiring lengkap ada di `case/lokana_wiring.png`, cara rakit di `case/README.md`.

## 1. Elektronik (per unit)

| Ref | Komponen | Jml | Spesifikasi / catatan | Kata kunci belanja |
|---|---|---|---|---|
| U1 | ESP32-C3 Super Mini | 1 | Type-C, 22.5 × 18 mm | `esp32 c3 super mini` |
| U2 | OLED 0.96" SSD1306 I2C 128×64 | 1 | 4 pin. Cek urutan pin (GND-VCC atau VCC-GND) | `oled 0.96 i2c 4 pin` |
| U3 | Modul charger TP4056 Type-C **+ proteksi** | 1 | 6 pad (B+ B− OUT+ OUT− IN+ IN−), chip DW01A + 8205A | `tp4056 type c proteksi` |
| U4 | Sensor sentuh TTP223 mini | 1 | 11.5 × 8 mm, jumper bawaan (output aktif HIGH) | `ttp223 mini` |
| BT1 | Baterai LiPo **102530** 3.7 V ±700 mAh | 1 | Sudah ada PCM/proteksi; maks 26 × 31 × 10 mm termasuk PCM | `lipo 102530` |
| SW1 | Saklar geser SS12D00 | 1 | 3 kaki, tuas 4 mm | `ss12d00` |
| BZ1 | Buzzer **pasif** 9 × 5.5 mm, 3 V | 1 | Magnetik, kumparan ±16 Ω, **wajib lewat Q1** | `passive buzzer 9055 3v` |
| Q1 | Transistor NPN S8050 SOT-23 (J3Y) | 1 | Atau MMBT2222A, atau **2SC1815 SOT-23** (marking HF, Ic maks 150 mA; cukup karena buzzer ±30–50 mA). Pin 1=B, 2=E, 3=C (cek marking/datasheet penjual) | `s8050 sot23` |
| D1 | Dioda Schottky SS14 (SMA) / B5819W (SOD-123) | 1 | Baterai → pin 5V Super Mini | `ss14 smd` |
| D2 | Dioda Schottky SS14 / B5819W | 0–1 | **Opsional**: port kanan ikut mengisi baterai | — |
| D3 | Dioda Schottky SS14 / B5819W | 1 | Paralel buzzer, katoda ke + | — |
| R0 | Resistor SMD 0603 **2.7 kΩ** (kode "272") | 1 | **Rprog TP4056**, ganti R3 bawaan 1.2 kΩ (kode "122"). Charge ±440 mA | `resistor 0603 2k7` |
| R1, R2 | Resistor SMD 0805 **100 kΩ** | 2 | Pembagi tegangan baterai → GPIO1 | `resistor 0805 100k` |
| R3, R4 | Resistor SMD 0805 100 kΩ | 0–2 | **Opsional**: deteksi charge IN+ → GPIO4 | — |
| R5 | Resistor SMD 0805 **1 kΩ** | 1 | Basis Q1. 1–1.5 kΩ sah (arus basis ±2–2.7 mA dari GPIO 3.3 V) | `resistor 0805 1k` |
| C1 | Kapasitor SMD 0805 **100 nF** | 1 | GPIO1 ke GND, penstabil ADC. 100–220 nF sah (RC ±5–11 ms) | `kapasitor 0805 100nf` |

**Unit pertama (dirakit 2026-11-21):** Q1 = 2SC1815 SOT-23, R5 = 1.2 kΩ, C1 = 220 nF, Rprog = 2.7 kΩ. Semua masih
dalam rentang di atas; firmware sama.

Lebih praktis beli **kit resistor SMD 0603/0805** dan **kit kapasitor 0805** daripada satu per satu.
Nilai 2.7 kΩ, 100 kΩ, 1 kΩ, dan 100 nF biasanya sudah ada di kit.

## 2. Casing dan bahan rakit (per unit)

| Bahan | Jml | Catatan |
|---|---|---|
| Casing Lokana Cube v1.1 (badan + tutup) | 1 set | PETG eSUN translucent pink, ±9 g, ±46 menit (preset 0.12 mm Fine) |
| Kabel silikon 30 AWG | ±50 cm | Beberapa warna (merah, hitam, oranye, hijau, kuning, biru, ungu) |
| Selotip kapton 10 mm | ±10 cm | Isolasi antar-board dan di depan baterai |
| Double tape busa tipis | ±5 cm | Menempelkan board dan baterai |
| Lem tembak (hot glue) | sedikit | Saklar, buzzer, sensor sentuh. **Jangan** super glue (uapnya mengaburkan PETG dan kaca OLED) |
| Heat shrink 1.5–2 mm | ±10 cm | Membungkus Q1, R, dan dioda yang disolder di kabel |
| Ring gantungan kunci | 1 | Kawat ≤ 2 mm (lubang kuping Ø3 mm) |

## 3. Alat

Solder mata kecil, timah 0.5–0.6 mm, flux, pinset, multimeter, **USB tester Type-C** (ukur arus charge dan
konsumsi daya), kabel data USB-C, printer 3D, cutter/amplas halus untuk merapikan hasil print.

## 4. Belanja untuk 3 unit (dengan cadangan)

| Barang | Beli | Untuk 3 unit |
|---|---|---|
| ESP32-C3 Super Mini | 4 | 3 + 1 cadangan |
| OLED 0.96" | 4 | 3 + 1 |
| TP4056 Type-C + proteksi | 5 | sering dijual per 5 |
| LiPo 102530 | 3 | |
| TTP223 mini | 5 | |
| Buzzer pasif 9 × 5.5 | 4 | |
| SS12D00 | 1 pack (10) | |
| SS14 / B5819W | 1 pack (20) | 2–3 per unit |
| S8050 SOT-23 | 1 pack (20) | |
| Kit resistor SMD 0603 + 0805, kapasitor 100 nF 0805 | 1 set | |
| Kabel silikon 30 AWG, kapton, double tape, heat shrink, ring | 1 set | |

## 5. Pin (ringkas)

| Fungsi | Pin Super Mini |
|---|---|
| OLED SDA / SCL | GPIO8 / GPIO9 |
| Sensor sentuh | GPIO3 |
| Buzzer (lewat Q1) | GPIO10 |
| Baterai (ADC, pembagi 2.0) | GPIO1 |
| Deteksi charge (opsional) | GPIO4 |
| Daya baterai | pin 5V (lewat D1) |
