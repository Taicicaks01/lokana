# Lokana Cube v1.1 — case 3D print

Case kubus untuk Lokana: **31.3 × 35.0 × 27.7 mm** (lebar × tinggi × tebal), ditambah kuping
gantungan kunci 5 mm di atas. Status: **prototipe uji pas (*fit test*)**, ukuran komponen
diambil dari katalog dan belum diukur langsung.

| File | Isi |
|---|---|
| `lokana_cube_v1.1_badan.stl` | Badan (layar, port program kanan, port charge bawah, saklar, sensor sentuh, kuping, rusuk penahan) |
| `lokana_cube_v1.1_tutup.stl` | Tutup belakang (jepit friksi + takik kuku) |
| `lokana_cube_v1.1.step` | Model lengkap + mockup komponen, untuk dibuka di Fusion |
| `lokana_case_v1.py` | Skrip Fusion parametrik; semua ukuran ada di `P` di bagian atas |
| `lokana_wiring.png` | Diagram wiring + tabel sambungan (A4 landscape, siap cetak) |
| `lokana_urutan_rakit.png` | Urutan perakitan per lapisan, dilihat dari belakang |

**v1.1:** rusuk penahan 1.45 mm (bisa dicetak tanpa support) di atas Super Mini, atas TP4056,
atas & bawah saklar, dan atas buzzer. Board tidak lagi bergeser ke samping; perekat cukup double
tape busa dan setitik lem tembak.

## Susunan komponen

```
 depan                                                    belakang
 [layar] OLED 0.96" → Super Mini → TP4056 Type-C → LiPo 102530 → [tutup]
           4.3 mm      4.5 mm       4.9 mm          10 mm

 Tampak depan:      ┌───────────────┐   ← kuping gantungan + titik sentuh di atas
                    │  ┌─────────┐  │ ◄ lubang suara buzzer (kanan atas)
                    │  │  layar  │  │
     saklar (kiri) ▸│  └─────────┘  ▐ ◄ USB-C PROGRAM (kanan)
                    └─────[USB]─────┘   ← USB-C CHARGE (bawah)
```

- **USB-C program/data (sisi kanan)** milik Super Mini: upload firmware, serial, dan daya
  saat Mode Meja. Lokana tetap bisa berdiri di meja saat port ini dicolok.
- **USB-C charge (bawah)** milik TP4056: untuk mengisi baterai.
- **Sisi kiri:** celah tuas saklar SS12D00. **Kanan atas:** 5 lubang suara buzzer.
- **Atas:** cekungan Ø6 mm sebagai penanda titik sentuh; sensor 11.5 × 8 mm menempel di
  kantong bagian dalam (dinding tersisa ±0.7 mm).
- Super Mini **berbaring** di bagian bawah, merapat ke dinding kanan (USB-C ke kanan).
  TP4056 tegak merapat ke dinding kiri (USB-C ke bawah). PCB keduanya menghadap depan.

## Pengaturan print

| Bagian | Orientasi | Support |
|---|---|---|
| Badan | **Muka layar menempel ke bed** | Hanya untuk kuping (*support on build plate only*) |
| Tutup | Muka luar menempel ke bed, lidah jepit menghadap atas | Tidak perlu |

- Bahan: **PLA** untuk uji pas; **PETG** untuk versi pakai (lebih tahan banting dan panas).
- Layer 0.12–0.16 mm (muka depan lebih halus), 3–4 dinding (*perimeters*), infill 20%.
- Matikan *elephant foot* berlebihan atau pakai kompensasi 0.1–0.2 mm, karena muka depan
  dan jendela layar ada di layer pertama.

## Perakitan (dua port)

```
 USB-C bawah ── TP4056 + DW01A (Rprog 4.7 kΩ ≈ 255 mA untuk 700 mAh)
                 B+/B- ── LiPo 102530 (lewat konektor JST)
                 OUT+ ── saklar ──┬── D1 Schottky ►| ── pin 5V Super Mini ── USB-C kanan
                                  │
                                 [R1 100k]          Pembagi tegangan baterai
                                  ├────── GPIO1 (ADC)   + kapasitor 100 nF ke GND
                                 [R2 100k]          (firmware: -DPIN_BATT=1, BATT_DIVIDER 2.0)
                                  │
                 OUT- ────────────┴────────────────── GND
 Opsional deteksi charge: IN+ TP4056 ── 100k ──┬── GPIO4 (ADC: > 2.1 V = charger dicolok)
                                               100k
                                               └── GND
 Opsional D2: pin 5V Super Mini ── Schottky ►| ── IN+ TP4056
              (supaya port kanan juga mengisi baterai saat Mode Meja)
 D1, D2: B5819W / SS14
 OLED:   SDA GPIO8, SCL GPIO9, VCC 3V3, GND
 Sentuh: OUT GPIO3, VCC 3V3, GND        Buzzer: GPIO10, GND
```

| Kondisi | Yang terjadi |
|---|---|
| Port kanan dicolok | Lokana jalan dari USB, upload/serial normal. D1 menahan 5 V agar tidak masuk ke baterai. Dengan D2, baterai ikut di-charge |
| Port bawah dicolok | Baterai di-charge oleh TP4056 |
| Tanpa kabel, saklar nyala | Baterai → D1 → pin 5V |
| Saklar mati | Baterai terputus dari Lokana; charge lewat port bawah tetap jalan |

**Monitoring baterai:** pembagi tegangan dipasang **setelah saklar dan sebelum D1**. Jadi yang
terbaca adalah tegangan baterai asli (tidak terpotong dioda), dan pembagi tidak menguras baterai
saat saklar mati. Tegangan 4.2 V terbaca 2.1 V di GPIO1, masih di dalam rentang ADC ESP32-C3
(±2.5 V pada atenuasi 11 dB). Kalau R1 ≠ R2, sesuaikan `BATT_DIVIDER = (R1 + R2) / R2`.

1. Cabut header pin semua modul; pakai kabel silikon tipis (28–30 AWG), sependek mungkin.
2. **Ganti Rprog TP4056** sesuai baterai (bawaan 1.2 kΩ = 1 A, terlalu besar).
3. Masukkan dari belakang, berurutan: OLED (kaca ke jendela) → Super Mini → TP4056.
   Lapisi dengan selotip kapton di antara board dan di depan baterai.
4. Saklar di sisi kiri, buzzer di kanan atas, sensor sentuh di kantong atas. Rekatkan dengan lem tembak/UHU.
5. Baterai paling belakang, lalu tekan tutup sampai rata. Kalau terlalu longgar, tambah selotip
   di lidah jepit; kalau terlalu sesak, amplas sedikit.
6. Charge lewat port bawah sebaiknya dengan **saklar mati**, supaya TP4056 bisa mendeteksi baterai penuh.

## Cek setelah print pertama

| Cek | Kalau tidak pas, ubah di `P` |
|---|---|
| Area menyala OLED pas di tengah jendela | `win_from_top`, `oled_glass_from_top` |
| OLED masuk rongga tanpa dipaksa | `oled_w`, `oled_h`, `clr` |
| Steker USB-C masuk penuh di kedua port | `usb_pocket`, posisi lewat `pcb_t`, `usbc_t`, `board_inset` |
| Tuas saklar bisa digeser penuh | `sw_slot_len`, `sw_slot_w` |
| Sensor sentuh bereaksi dari luar | `touch_pocket` (lebih dalam = dinding lebih tipis) |
| Tutup menjepit tapi bisa dibuka | `tab_t`, `tab_len` |
| Baterai muat | `bat_w`, `bat_l`, `bat_t` |

Setelah mengubah angka: jalankan `lokana_case_v1.py` di Fusion (skrip menghapus timeline lalu
membangun ulang), cek tabrakan, lalu ekspor STL lagi.

## Ukuran yang dipakai v1 (katalog)

| Komponen | Ukuran (mm) |
|---|---|
| OLED 0.96" (PCB / kaca / tebal) | 27.3 × 27.8 / 26.7 × 19.26 / 4.3 |
| ESP32-C3 Super Mini | 22.5 × 18 × 4.5 |
| TP4056 Type-C + proteksi | 28 × 17.3 × 4.9 |
| LiPo 102530 (maks, termasuk proteksi) | 26 × 31 × 10 |
| Saklar SS12D00 | 8.5 × 3.5 × 4.4 |
| Buzzer pasif | Ø9 × 5.5 |
| Sensor sentuh | 11.5 × 8 |
