# Lokana Link — Spesifikasi Protokol v1

> **Status:** v1, diimplementasikan sebagian sejak **Lokana OS 0.3.0**; pesan bertanda v0.3 dan
> v0.4 di [Daftar pesan](#5-daftar-pesan) sudah ada di **Lokana OS 0.4.0**. Perubahan masih boleh selama belum ada rilis resmi. Setelah dirilis, ikuti [aturan kompatibilitas](#9-aturan-kompatibilitas).

Lokana Link adalah satu format pesan untuk semua komunikasi dengan Lokana:
**aplikasi HP lewat BLE**, **Lokana Desktop lewat USB serial**, dan **Lokana Desktop lewat WiFi UDP**.
Firmware memakai satu *parser* yang sama untuk ketiganya.

## Daftar isi

1. [Istilah](#1-istilah)
2. [Frame](#2-frame)
3. [Transport](#3-transport)
4. [Tipe data](#4-tipe-data)
5. [Daftar pesan](#5-daftar-pesan)
6. [Detail payload](#6-detail-payload)
7. [Alur umum](#7-alur-umum)
8. [Keamanan](#8-keamanan)
9. [Aturan kompatibilitas](#9-aturan-kompatibilitas)
10. [Contoh byte](#10-contoh-byte)

---

## 1. Istilah

| Istilah | Arti |
|---|---|
| **Device** | Lokana (ESP32-C3, Lokana OS) |
| **Host** | Pihak lain: aplikasi Lokana (HP), Lokana Desktop, atau skrip uji |
| **Frame** | Satu pesan Lokana Link: header + payload |
| **Envelope** | Pembungkus frame untuk transport yang tidak andal (USB, UDP): penanda awal + CRC |
| `str` | String UTF-8 dengan panjang di depan (lihat [Tipe data](#4-tipe-data)) |

Semua angka multi-byte memakai **little-endian**.

---

## 2. Frame

```
 0        1        2        3        4 ...
┌────────┬────────┬────────┬────────┬──────────────────┐
│ type   │ seq    │ len (u16 LE)    │ payload (len B)  │
└────────┴────────┴────────┴────────┴──────────────────┘
```

| Field | Ukuran | Keterangan |
|---|---|---|
| `type` | u8 | Jenis pesan (lihat [Daftar pesan](#5-daftar-pesan)) |
| `seq` | u8 | `0` = tidak minta balasan. `1–255` = penerima **wajib** membalas `ACK` dengan `seq` yang sama |
| `len` | u16 | Panjang payload dalam byte |
| `payload` | `len` | Isi pesan |

- Ukuran payload maksimum: **1200 byte** (`LK_MAX_PAYLOAD`). Frame yang lebih besar dibuang
  dan, jika `seq ≠ 0`, dibalas `ACK` status `BAD_PAYLOAD`.
- Host memilih `seq` berurutan 1, 2, …, 255, 1, … dan menunggu `ACK` maksimal **2 detik**
  sebelum mengirim ulang (maksimal 3 kali).

---

## 3. Transport

### 3.1 BLE (aplikasi HP)

Satu *GATT service* custom dengan dua *characteristic*, mirip pola UART:

| Bagian | UUID | Properti |
|---|---|---|
| Service **Lokana Link** | `6c6f6b61-0000-4c4b-8000-6c6f6b616e61` | — |
| **RX** (host → device) | `6c6f6b61-0001-4c4b-8000-6c6f6b616e61` | Write, Write Without Response (terenkripsi) |
| **TX** (device → host) | `6c6f6b61-0002-4c4b-8000-6c6f6b616e61` | Notify (terenkripsi) |

- RX dan TX diperlakukan sebagai **aliran byte** (*byte stream*). Frame boleh terpotong ke
  beberapa *write*/*notify*, dan satu *write* boleh berisi beberapa frame. Penerima menyusun
  ulang berdasarkan `len`. BLE sudah punya CRC sendiri, jadi **tanpa envelope**.
- Host meminta MTU **247**. Potongan data per *write* = `MTU − 3`.
- Nama iklan (*advertising name*): `Lokana-XXXX` (`XXXX` = 2 byte terakhir alamat MAC, hex).
  UUID service ikut diiklankan di *scan response* supaya aplikasi bisa memfilter.
- Kalau parser menunggu lanjutan frame lebih dari **1 detik**, buffer dibuang (*resync*).
- Begitu host tersambung, device langsung meminta keamanan (*security request*): HP yang belum
  pernah pairing akan diminta passkey, HP yang sudah *bonded* cukup mengenkripsi ulang.
  Notify TX hanya dikirim setelah koneksi terenkripsi dan terautentikasi.
- Pesan D→H tanpa diminta dikirim setelah host mengirim `HELLO` pada koneksi itu, sampai koneksi putus.

Remote presentasi, media keys, dan Win+L memakai **BLE HID** standar di service terpisah,
bukan Lokana Link.

### 3.2 USB serial (Lokana Desktop, skrip uji)

USB CDC 115200 baud juga dipakai untuk console teks (`help`, `info`, …). Frame biner
dibungkus envelope supaya bisa dibedakan dari teks:

```
┌──────┬──────┬───────────────────────┬─────────────────┐
│ 0xA5 │ 0x5A │ frame (header+payload)│ crc16 (u16 LE)  │
└──────┴──────┴───────────────────────┴─────────────────┘
```

- **CRC-16/CCITT-FALSE**: polinomial `0x1021`, nilai awal `0xFFFF`, tanpa refleksi, tanpa XOR akhir.
  Dihitung atas **frame** saja (tanpa `A5 5A`). Nilai uji: `"123456789"` → `0x29B1`.
- Byte di luar envelope adalah teks console. Byte `0xA5` tidak pernah muncul di teks ASCII.
- Frame dengan CRC salah dibuang tanpa balasan; host akan mengirim ulang setelah *timeout*.
- Device boleh mengirim log teks di antara frame. Host mencari `A5 5A` untuk menemukan frame.
- Pesan D→H **tanpa diminta** (`DICE` hasil, `BUTTON`, `FIND_PHONE`, `SETTINGS` REPORT karena
  perubahan di device) hanya dikirim lewat USB setelah host mengirim `HELLO` di USB. Begitu ada
  teks console masuk (orang mengetik di serial monitor), pengiriman ini berhenti sampai `HELLO`
  berikutnya, supaya serial monitor tidak dibanjiri byte biner.

### 3.3 WiFi UDP (Lokana Desktop)

- Port UDP **4747**. Satu datagram = satu envelope (format sama dengan USB).
- Device mengumumkan diri lewat mDNS: host `lokana-xxxx.local`, service `_lokana._udp`.
- Hanya pesan berikut yang diterima lewat UDP: `HELLO`, `TIME_SYNC`, `PC_STATS`,
  `MEETING`, `CUSTOM_TEXT`. Pesan lain dibalas `ACK` status `NOT_ALLOWED` (lihat [Keamanan](#8-keamanan)).

---

## 4. Tipe data

| Tipe | Ukuran | Keterangan |
|---|---|---|
| `u8` `u16` `u32` | 1 / 2 / 4 | Bilangan tak bertanda, little-endian |
| `i8` `i16` `i32` | 1 / 2 / 4 | Bilangan bertanda, *two's complement* |
| `str` | 1 + n | `u8` panjang (0–255) diikuti `n` byte UTF-8, **tanpa** null di akhir |
| `bitmap` | `ceil(w/8) × h` | 1 bit per piksel, baris demi baris, bit paling kiri = MSB, `1` = piksel menyala |

**Teks di layar:** font OLED hanya mendukung ASCII. Device mengganti karakter yang tidak
bisa ditampilkan dengan `?`. Host sebaiknya mengubah huruf beraksen ke ASCII (é → e) dan
mengirim emoji sebagai `BITMAP`.

---

## 5. Daftar pesan

Arah: **H→D** host ke device, **D→H** device ke host.

| Type | Nama | Arah | Ringkasan | Versi firmware |
|---|---|---|---|---|
| **Sistem** | | | | |
| `0x00` | `HELLO` | H→D | Perkenalan host; device membalas `DEVICE_INFO` | v0.3 |
| `0x01` | `TIME_SYNC` | H→D | Waktu UTC + zona waktu | v0.3 |
| `0x02` | `DEVICE_INFO` | D→H | Jenis device, versi, layar, baterai, kemampuan | v0.3 |
| `0x03` | `SETTINGS` | dua arah | Baca/ubah pengaturan | v0.4 |
| `0x04` | `OTA` | dua arah | Update firmware (begin/chunk/end/abort) | v0.9 |
| `0x05` | `ACK` | dua arah | Balasan untuk frame dengan `seq ≠ 0` | v0.3 |
| **Informasi** | | | | |
| `0x10` | `NOTIF` | H→D | Notifikasi HP (tampil / hapus) | v0.5 |
| `0x11` | `NAV` | H→D | Navigasi: panah, jarak, instruksi | v0.6 |
| `0x12` | `PC_STATS` | H→D | Daftar metrik komputer | v0.7 |
| `0x13` | `MEETING` | H→D | Status rapat (mikrofon/kamera) | v0.7 |
| `0x14` | `PHONE_STATS` | H→D | Daftar metrik HP | v0.7 |
| `0x15` | `CALL` | H→D | Panggilan masuk / selesai | v0.5 |
| **Aksi** | | | | |
| `0x20` | `FIND_KEYS` | H→D | Bunyikan Lokana / hentikan | v0.3 |
| `0x21` | `FIND_PHONE` | dua arah | Minta HP berbunyi / hentikan | v0.4 |
| `0x22` | `EXPRESSION` | H→D | Ubah ekspresi Lokana | v0.3 |
| `0x23` | `DICE` | dua arah | Minta lempar dadu / hasil lemparan | v0.4 |
| `0x24` | `GOTO` | H→D | Buka modul tertentu | v0.3 |
| `0x25` | `BUTTON` | D→H | Gestur tombol (untuk pintasan di aplikasi) | v0.4 |
| **Tampilan** | | | | |
| `0x30` | `CUSTOM_TEXT` | H→D | Teks custom | v0.3 |
| `0x31` | `BITMAP` | H→D | Gambar/emoji 1-bit | v0.4 |
| **Jaringan** | | | | |
| `0x40` | `WIFI_PROV` | H→D | Simpan / hapus WiFi | v0.8 |
| `0x41` | `WIFI_STATUS` | D→H | Status koneksi WiFi | v0.8 |

Rentang cadangan: `0x50–0x6F` untuk pesan resmi berikutnya, `0x70–0x7F` eksperimental,
`0x80–0xFF` untuk fork/turunan komunitas (tidak akan dipakai versi resmi).

---

## 6. Detail payload

### `0x00` HELLO (H→D)

| Field | Tipe | Keterangan |
|---|---|---|
| `proto_ver` | u8 | Versi protokol host, saat ini `1` |
| `client_type` | u8 | `1` Android, `2` iOS, `3` Lokana Desktop, `4` skrip/uji |
| `client_name` | str | Contoh `"Lokana Android 0.4.0"` |

Device membalas `DEVICE_INFO`. `HELLO` harus menjadi pesan pertama setiap koneksi.

### `0x01` TIME_SYNC (H→D)

| Field | Tipe | Keterangan |
|---|---|---|
| `epoch` | u32 | Detik sejak 1970-01-01 UTC |
| `tz_offset_min` | i16 | Selisih zona waktu dalam menit. WIB `420`, WITA `480`, WIT `540` |

`epoch` sebelum 2023-11-14 (`< 1700000000`) dibalas `BAD_PAYLOAD`. Tanpa `tz_offset_min`,
device memakai zona waktu terakhir. Zona waktu disimpan di flash.

### `0x02` DEVICE_INFO (D→H)

| Field | Tipe | Keterangan |
|---|---|---|
| `proto_ver` | u8 | `1` |
| `device_type` | u8 | `1` = Lokana. Gadget berikutnya memakai nomor lain |
| `fw_version` | str | Contoh `"0.3.0"` |
| `screen_w` | u16 | Lebar layar (128) |
| `screen_h` | u16 | Tinggi layar (64 atau 32) |
| `battery_pct` | u8 | 0–100, `255` = tidak diketahui |
| `flags` | u8 | bit0 USB/mengisi daya, bit1 WiFi tersambung, bit2 sudah *bonded* |
| `caps` | u32 | Kemampuan (lihat di bawah) |
| `device_name` | str | Nama pemilik/alat dari `SETTINGS`, contoh `"Lokana Wayan"`. Belum diatur = nama iklan BLE (`Lokana-XXXX`) |

Device tanpa sensor baterai (`battery_pct = 255`) dianggap mendapat daya dari USB (bit0 = 1).

Bit `caps`: 0 `NOTIF` · 1 `NAV` · 2 `PC_STATS` · 3 `PHONE_STATS` · 4 `CUSTOM_TEXT` ·
5 `BITMAP` · 6 `OTA` · 7 `WIFI` · 8 `HID` · 9 `BUZZER` · 10 `DICE` · 11 `FIND_PHONE`.
Aplikasi menyembunyikan menu untuk kemampuan yang tidak dimiliki device.

### `0x03` SETTINGS (dua arah)

| Field | Tipe | Keterangan |
|---|---|---|
| `op` | u8 | `0` GET (H→D), `1` SET (H→D), `2` REPORT (D→H) |
| `items` | TLV… | Daftar `key u8` · `len u8` · `value` (kosong untuk GET = minta semua) |

| Key | Nama | Nilai |
|---|---|---|
| `0x01` | brightness | u8: `0` redup, `1` sedang, `2` terang |
| `0x02` | sound | u8: `0` mati, `1` nyala |
| `0x03` | screen_timeout | u16 detik, `0` = tidak pernah mati |
| `0x04` | flip | u8: `0` normal, `1` diputar 180° |
| `0x05` | device_name | UTF-8, maks 24 byte. Kosong = kembali ke nama bawaan |
| `0x06` | button_events | u8: `1` kirim `BUTTON` ke host ini, `0` tidak (bawaan). **Tidak disimpan**: kembali `0` saat koneksi putus |

Setelah GET atau SET, device mengirim `ACK` (jika `seq ≠ 0`) lalu `REPORT` berisi semua
pengaturan saat ini ke host yang meminta. Pengaturan yang diubah dari menu Lokana juga
dikirim sebagai `REPORT` (`seq = 0`) ke host yang sudah `HELLO`.

- Key yang tidak dikenal diabaikan. Item yang terpotong (`len` melebihi sisa payload) = `BAD_PAYLOAD`,
  dan tidak ada pengaturan yang berubah.
- Nilai `screen_timeout` dibulatkan ke pilihan terdekat yang didukung firmware
  (15, 30, 60, 300 detik, atau `0`).
- `device_name` hanya mengubah nama di `DEVICE_INFO` dan layar Info. Nama iklan BLE tetap
  `Lokana-XXXX` supaya mudah dikenali saat scan.
- `op` = `2` dari host dibalas `BAD_PAYLOAD`; `op` lain yang tidak dikenal dibalas `NOT_SUPPORTED`.

### `0x04` OTA (dua arah)

| `op` | Arah | Field setelah `op` |
|---|---|---|
| `0` BEGIN | H→D | `size u32`, `sha256 [32]`, `version str` |
| `1` CHUNK | H→D | `offset u32`, data (sisa payload, disarankan 512 B) |
| `2` END | H→D | — |
| `3` ABORT | dua arah | `reason u8` |
| `4` PROGRESS | D→H | `received u32` |

Setiap BEGIN/CHUNK/END dikirim dengan `seq ≠ 0`. Device menulis ke slot OTA cadangan,
memeriksa SHA-256 saat END, lalu restart. Firmware baru menandai dirinya valid setelah
berhasil boot; jika gagal, bootloader kembali ke versi lama (*rollback*). Hanya diizinkan
lewat BLE terenkripsi atau USB.

### `0x05` ACK (dua arah)

`seq` pada header ACK = `seq` frame yang dibalas.

| Field | Tipe | Keterangan |
|---|---|---|
| `acked_type` | u8 | `type` frame yang dibalas |
| `status` | u8 | lihat tabel |

| Status | Nama | Arti |
|---|---|---|
| `0` | `OK` | Diterima dan diproses |
| `1` | `UNKNOWN_TYPE` | Tipe tidak dikenal |
| `2` | `BAD_PAYLOAD` | Payload terlalu pendek/panjang atau rusak |
| `3` | `BUSY` | Sedang sibuk (mis. OTA berjalan), coba lagi |
| `4` | `NOT_SUPPORTED` | Dikenal tapi tidak didukung device ini |
| `5` | `NOT_ALLOWED` | Tidak diizinkan lewat transport ini / belum *bonded* |
| `6` | `ERROR` | Gagal karena sebab lain |

### `0x10` NOTIF (H→D)

| Field | Tipe | Keterangan |
|---|---|---|
| `op` | u8 | `0` tampilkan/perbarui, `1` hapus |
| `id` | u32 | ID unik dari host; notifikasi dengan ID sama diperbarui, bukan ditumpuk |
| `category` | u8 | `0` umum, `1` pesan, `2` email, `3` media sosial, `4` kalender, `5` panggilan tak terjawab, `6` sistem |
| `flags` | u8 | bit0 tanpa bunyi, bit1 penting |
| `app` | str | Nama aplikasi, contoh `"WhatsApp"` |
| `title` | str | Judul/pengirim |
| `body` | str | Isi; host memotong maks **160 byte** |

Untuk `op = 1`, cukup `op` dan `id`. Device menyimpan maksimal 8 notifikasi terakhir di RAM
dan tidak menyimpannya ke flash.

### `0x11` NAV (H→D)

| Field | Tipe | Keterangan |
|---|---|---|
| `state` | u8 | `0` navigasi aktif, `1` selesai/berhenti |
| `distance_m` | u32 | Jarak ke belokan berikutnya; `0xFFFFFFFF` = tidak diketahui |
| `distance_text` | str | Teks jarak dari Maps, contoh `"200 m"` |
| `instruction` | str | Contoh `"Belok kanan"` |
| `street` | str | Nama jalan, contoh `"Jl. Udayana"` |
| `eta_min` | u16 | Sisa waktu ke tujuan, `0xFFFF` = tidak diketahui |
| `icon_w` | u8 | Lebar ikon panah (0 = tanpa ikon, maks 32) |
| `icon_h` | u8 | Tinggi ikon (maks 32) |
| `icon` | bitmap | Ikon panah 1-bit dari notifikasi Google Maps |

### `0x12` PC_STATS · `0x14` PHONE_STATS (H→D)

Keduanya memakai format **daftar metrik** yang sama. Host menentukan metrik apa yang
dikirim; device hanya menampilkan. Jadi metrik baru tidak butuh update firmware.

| Field | Tipe | Keterangan |
|---|---|---|
| `count` | u8 | Jumlah metrik (maks 12) |
| `metrics` | … × `count` | Lihat di bawah |

Setiap metrik:

| Field | Tipe | Keterangan |
|---|---|---|
| `kind` | u8 | `0` angka, `1` persen (ditampilkan dengan bar), `2` suhu |
| `label` | str | Maks 6 karakter, contoh `"CPU"`, `"GPU°"`, `"RAM"` |
| `value_x10` | i32 | Nilai × 10, contoh `45.3` → `453` |
| `unit` | str | Maks 4 karakter, contoh `"%"`, `"C"`, `"MB/s"` |

Host mengirim setiap **2–3 detik**. Jika tidak ada data selama **10 detik**, device
menganggap PC/HP terputus dan kembali ke tampilan jam.

### `0x13` MEETING (H→D)

| Field | Tipe | Keterangan |
|---|---|---|
| `on` | u8 | `0` selesai, `1` sedang rapat |
| `mic` | u8 | `0` mati, `1` nyala, `255` tidak diketahui |
| `cam` | u8 | `0` mati, `1` nyala, `255` tidak diketahui |

### `0x15` CALL (H→D)

| Field | Tipe | Keterangan |
|---|---|---|
| `state` | u8 | `0` berdering, `1` selesai/ditolak/diangkat |
| `caller` | str | Nama kontak atau nomor |

### `0x20` FIND_KEYS (H→D)

| Field | Tipe | Keterangan |
|---|---|---|
| `op` | u8 | `1` mulai, `0` berhenti |
| `duration_s` | u8 | Lama bunyi, `0` atau tidak ada = 30. Tombol di Lokana juga menghentikannya |

Bunyi tetap keluar walaupun suara dimatikan di pengaturan.

### `0x21` FIND_PHONE (dua arah)

| Field | Tipe | Keterangan |
|---|---|---|
| `op` | u8 | `1` bunyikan HP, `0` hentikan |

- **D→H:** pengguna memilih **Cari HP** di menu Lokana (triple-tap). Layar "Memanggil HP"
  tampil maks 30 detik; tap atau waktu habis mengirim `op = 0`. Tanpa host BLE yang sudah
  `HELLO`, Lokana menampilkan "HP tidak tersambung".
- **H→D:** `op = 0` berarti HP sudah ditemukan (dihentikan dari HP); Lokana menutup layar
  "Memanggil HP". `op = 1` dari host dibalas `BAD_PAYLOAD`.

### `0x22` EXPRESSION (H→D)

| Field | Tipe | Keterangan |
|---|---|---|
| `expr` | u8 | ID ekspresi (tabel di bawah) |
| `hold_ms` | u16 | Lama ekspresi ditahan, `0` = default (4000 ms) |

| ID | Ekspresi | ID | Ekspresi | ID | Ekspresi |
|---|---|---|---|---|---|
| 0 | netral | 5 | kaget | 10 | semangat |
| 1 | senang | 6 | cinta | 11 | gugup |
| 2 | sedih | 7 | pusing | 12 | kedip |
| 3 | marah | 8 | curiga | | |
| 4 | ngantuk | 9 | bosan | | |

ID ini sama dengan urutan `enum Expression` di `firmware/src/core/face.h`.
ID yang belum dikenal firmware dibalas `NOT_SUPPORTED`.
Ekspresi baru **ditambahkan di akhir**, urutan lama tidak boleh diubah.

### `0x23` DICE (dua arah)

| Field | Tipe | Keterangan |
|---|---|---|
| `op` | u8 | `0` minta lempar (H→D), `1` hasil (D→H) |
| `dice` | u8 | `0` 1d6, `1` 2d6, `2` d4, `3` d8, `4` d10, `5` d12, `6` d20, `7` koin; `255` = jenis yang sedang dipilih |
| `count` | u8 | Hanya untuk hasil: jumlah nilai |
| `values` | u8 × `count` | Hanya untuk hasil. Koin: `0` angka, `1` gambar |

Device mengirim hasil setiap kali dadu dilempar, baik dari tombol maupun dari aplikasi.

- Permintaan lempar membuka modul Dadu dan mengganti jenis dadu jika `dice ≠ 255`. Hasil
  dikirim setelah animasi selesai (±1 detik), terpisah dari `ACK`.
- ID dadu yang belum dikenal firmware dibalas `NOT_SUPPORTED`. `op = 1` dari host dibalas `BAD_PAYLOAD`.
- `values` 2d6 berisi dua nilai (dadu kiri, kanan).

### `0x24` GOTO (H→D)

| Field | Tipe | Keterangan |
|---|---|---|
| `module` | str | Nama modul, tidak peka huruf besar/kecil: `"Lokana"`, `"Jam"`, `"Dadu"`, `"Teks"`, … |

Modul yang tidak ada, atau layar sistem (pairing, cari kunci), dibalas `ERROR`.

### `0x25` BUTTON (D→H)

| Field | Tipe | Keterangan |
|---|---|---|
| `gesture` | u8 | `1` tap, `2` double, `3` triple, `4` tahan |
| `module` | str | Modul yang sedang aktif |

Dikirim hanya ke host yang menyalakan `button_events` lewat `SETTINGS` (misal tap di modul
"Pintasan" = jalankan aksi di HP). Gestur tetap dijalankan Lokana seperti biasa; pesan ini
hanya pemberitahuan. Gestur di dalam menu (triple-tap) tidak dikirim.

### `0x30` CUSTOM_TEXT (H→D)

| Field | Tipe | Keterangan |
|---|---|---|
| `style` | u8 | `0` diam, `1` berjalan (*scroll*), `2` berkedip |
| `size` | u8 | `0` otomatis, `1`–`3` ukuran font |
| `duration_s` | u16 | `0` = tampil sampai ditutup dengan tombol |
| `slot` | u8 | `0` tampilkan sekarang, `1`–`8` simpan ke slot (name tag, pesan favorit) |
| `text` | str | Maks 200 byte. `\n` = baris baru |

- `style`/`size` yang belum dikenal diperlakukan sebagai `0`.
- `slot` > 8 dibalas `BAD_PAYLOAD`. Teks kosong ke slot 1–8 = hapus slot itu.
- Teks yang ditampilkan (`slot = 0`) ditutup dengan tap atau setelah `duration_s`, lalu
  Lokana kembali ke modul sebelumnya.

### `0x31` BITMAP (H→D)

| Field | Tipe | Keterangan |
|---|---|---|
| `op` | u8 | `0` tampilkan sekarang, `1` simpan ke slot |
| `slot` | u8 | `1`–`8` (untuk `op = 1`) |
| `duration_s` | u16 | `0` = sampai ditutup |
| `x` | i16 | Posisi kiri (biasanya `0`) |
| `y` | i16 | Posisi atas |
| `w` | u8 | Lebar, maks 128 |
| `h` | u8 | Tinggi, maks 64 |
| `data` | bitmap | `ceil(w/8) × h` byte; layar penuh 128×64 = 1024 byte |

- `w` > 128 atau `h` > 64, atau `data` kurang dari `ceil(w/8) × h` byte = `BAD_PAYLOAD`.
  Byte `data` berlebih diabaikan.
- `op = 1` dengan `w = 0` atau `h = 0` = hapus slot itu. Slot di luar `1–8` = `BAD_PAYLOAD`.
  `op` lain yang tidak dikenal dibalas `NOT_SUPPORTED`.
- Gambar yang ditampilkan (`op = 0`) muncul di modul **Gambar** di atas latar hitam, ditutup
  dengan tap atau setelah `duration_s`, lalu Lokana kembali ke modul sebelumnya. Slot
  tersimpan di flash (littlefs) dan bisa dilihat bergantian di modul Gambar.

### `0x40` WIFI_PROV (H→D)

| Field | Tipe | Keterangan |
|---|---|---|
| `op` | u8 | `0` simpan & sambungkan, `1` hapus |
| `ssid` | str | Maks 32 byte |
| `password` | str | Maks 64 byte |

Hanya diterima lewat **BLE terenkripsi** atau **USB**. Password tidak pernah dikirim balik
dan tidak pernah ditulis ke log serial.

### `0x41` WIFI_STATUS (D→H)

| Field | Tipe | Keterangan |
|---|---|---|
| `state` | u8 | `0` mati, `1` menyambung, `2` tersambung, `3` gagal |
| `ssid` | str | Nama jaringan |
| `rssi` | i8 | Kekuatan sinyal (dBm) |
| `ip` | u32 | Alamat IPv4 (byte pertama = oktet pertama), `0` jika belum ada |

---

## 7. Alur umum

### Sambung pertama kali (BLE)

```
Aplikasi                                Lokana
   │  scan: filter UUID service            │  advertising "Lokana-1A2B"
   │──────────── connect ─────────────────►│
   │◄──── minta pairing (passkey) ─────────│  OLED: "Kode: 482913"
   │  pengguna mengetik 482913             │
   │──────────── bonded ──────────────────►│  kunci tersimpan di NVS
   │  HELLO (seq=1)                        │
   │──────────────────────────────────────►│
   │◄─────────────── ACK(seq=1) + DEVICE_INFO
   │  TIME_SYNC, SETTINGS GET              │
   │──────────────────────────────────────►│
   │◄─────────────────── SETTINGS REPORT ──│
```

### Monitor PC (USB)

```
Lokana Desktop                          Lokana
   │  buka COM, kirim HELLO               │
   │─────────────────────────────────────►│
   │◄──────────────────────── DEVICE_INFO │
   │  TIME_SYNC                           │
   │  PC_STATS tiap 2–3 detik (seq=0)     │  modul Monitor tampil otomatis
   │─────────────────────────────────────►│
   │  (berhenti > 10 detik)               │  kembali ke modul sebelumnya
```

---

## 8. Keamanan

| Aturan | Alasan |
|---|---|
| Characteristic RX/TX BLE mewajibkan **enkripsi + bonding** | Orang asing tidak bisa mengirim pesan ke Lokana; syarat ANCS untuk iPhone |
| Pairing memakai **passkey 6 digit di OLED** (IO capability: *DisplayOnly*) | Mencegah *man-in-the-middle* saat pairing |
| `OTA`, `WIFI_PROV`, `SETTINGS SET` hanya lewat BLE terenkripsi atau USB | Pesan berbahaya tidak bisa dikirim dari jaringan |
| UDP hanya menerima pesan tampilan (`PC_STATS`, `MEETING`, `CUSTOM_TEXT`, `TIME_SYNC`, `HELLO`) | Jaringan lokal dianggap tidak tepercaya |
| Notifikasi tidak disimpan di flash; password WiFi tidak pernah di-log | Privasi |
| Hapus pairing: menu di Lokana → "Lupakan HP" | Saat Lokana dijual/dipindahtangankan |

---

## 9. Aturan kompatibilitas

1. **Field baru selalu ditambahkan di akhir payload.** Pembaca mengabaikan byte tambahan
   yang tidak dikenal dan memakai nilai default untuk field akhir yang tidak ada.
2. **Nomor `type` dan ID (ekspresi, dadu, key pengaturan) tidak pernah dipakai ulang**
   untuk arti lain.
3. Tipe yang tidak dikenal diabaikan; jika `seq ≠ 0`, dibalas `ACK` status `UNKNOWN_TYPE`.
4. Perubahan yang tidak kompatibel menaikkan `proto_ver`. Device yang menerima `HELLO` dengan
   `proto_ver` lebih tinggi tetap menjawab dengan versinya sendiri; host menyesuaikan diri.
5. Setiap perubahan spesifikasi dicatat di [Riwayat](#riwayat) dan di *changelog* rilis.

---

## 10. Contoh byte

**TIME_SYNC** untuk 16 Nov 2026 11:00 WITA (`epoch = 1794798000`, `tz = +480`), tanpa ACK:

```
frame:    01 00 06 00  b0 71 fa 6a  e0 01
          │  │  └─len  └─epoch      └─tz_offset_min
          │  └─seq
          └─type TIME_SYNC
```

Lewat **BLE**: tulis 10 byte `frame` di atas ke characteristic RX.

Lewat **USB/UDP** (dengan envelope dan CRC `0xE913`):

```
a5 5a  01 00 06 00 b0 71 fa 6a e0 01  13 e9
```

**ACK** dari device untuk frame `seq = 7` bertipe `CUSTOM_TEXT`:

```
05 07 02 00  30 00
│  │  └len   │  └status OK
│  └seq 7    └acked_type CUSTOM_TEXT
└ACK
```

---

## Riwayat

| Versi | Tanggal | Perubahan |
|---|---|---|
| v1 (draf) | 2026-11-16 | Draf pertama: frame dengan `seq`, transport BLE/USB/UDP, 22 tipe pesan |
| v1 | 2026-11-16 | Klarifikasi dari implementasi firmware 0.3.0 (tanpa perubahan format): security request saat BLE tersambung, batas `epoch` TIME_SYNC, field akhir opsional, `ERROR` untuk GOTO ke modul tidak ada/sistem, `NOT_SUPPORTED` untuk ID ekspresi baru, aturan `style`/`slot` CUSTOM_TEXT, bunyi FIND_KEYS mengabaikan setelan suara |
| v1 | 2026-11-16 | Untuk firmware 0.4.0 (tambahan, format lama tetap): key SETTINGS `0x06 button_events`; REPORT saat pengaturan diubah di device; aturan pesan D→H tanpa diminta (setelah `HELLO`, USB berhenti saat ada teks console); `FIND_PHONE` dua arah (`op 0` dari HP menutup layar); aturan validasi DICE dan BITMAP; hapus slot BITMAP dengan `w`/`h = 0` |
