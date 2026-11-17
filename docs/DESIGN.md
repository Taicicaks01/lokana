# Desain Aplikasi Lokana: "robot hidup"

Panduan visual dan interaksi untuk aplikasi Android Lokana. Targetnya: **lebih bagus dari aplikasi wearable di
pasaran**. Mockup ada di kanvas desain "Lokana App — desain" (https://claude.ai/artifact/LbQZ2P3K5U91jRud6y9LZx).
Layar Studio di mockup bisa dicoba: mengetik, ganti font, dan ganti gaya.

## 1. Prinsip

1. **Lokana selalu hidup.** Perangkatnya tampil sebagai Lokana Cube pink yang matanya berkedip, bukan foto
   statis. Ekspresinya ikut status: berkedip saat terhubung, melirik kiri-kanan saat mencari, mengantuk saat
   terputus atau menyambung ulang, senang sebentar saat perintah berhasil (ACK).
2. **Pratinjau jujur.** Apa pun yang dikirim tampil dulu di pratinjau OLED **1:1 piksel** (pakai `render.dart`
   dan `oled_fonts.dart` yang sudah ada), dengan grid piksel tipis dan sedikit glow. Kata-katanya: "Pratinjau
   sama persis dengan layar Lokana".
3. **Dangkal dan cepat.** Empat tab. Fitur apa pun paling jauh dua ketukan dari Beranda. Tanpa akun, tanpa login,
   tanpa iklan, tetap jalan offline.
4. **Satu aksi utama per layar.** Hanya aksi utama yang pink penuh (Cari kunci, Tampilkan, Sambungkan). Sisanya
   permukaan netral.
5. **Tidak ada data palsu.** Chip baterai hanya muncul kalau firmware mengirim persen asli (setelah v0.5.5).
   Sinyal diambil dari RSSI. Kalau firmware belum mendukung, tampilkan petunjuk "Perlu Lokana OS x.y", jangan
   tombol mati tanpa alasan.

## 2. Token

| Token | Gelap | Terang | Catatan |
|---|---|---|---|
| bg | `#121016` | `#FBF7F9` | latar halaman |
| surface | `#1C1920` | `#FFFFFF` | kartu |
| surface2 | `#26222B` | `#F3ECF0` | segmen, isian dalam kartu |
| line | putih 8% | `#1B1720` 8% | garis dan tepi kartu |
| text | `#F6F1F5` | `#1B1720` | |
| muted | `#A69CA8` | `#655D6A` | kontras ≥ 4.5:1 di kedua tema |
| pink (brand) | `#F478AA` | `#F478AA` | tombol utama, isian aktif; teks di atasnya `#2B0F1C` |
| pink sebagai teks | `#F78BB6` | `#B8336A` | label aktif, tautan |
| pink lembut | pink 16% | pink 18% | latar ikon, tab aktif |
| hero | `#0E0C11` | `#1A161E` | kartu hero **tetap gelap** di mode terang (itu "layar OLED") |
| OLED | pilihan pengguna (default `#9EE7FF`) | sama | mata dan pratinjau |
| status OK | `#6EE7A8` | `#6EE7A8` | titik "Tersambung" |

Warna aksen pilihan pengguna (`AppTheme.accent`) tetap menjadi seed `ColorScheme`. Bentuk Lokana Cube dan ikon
selalu pakai pink brand, apa pun aksennya.

**Huruf**: judul pakai Baloo 2 (sudah ada di `assets/fonts`), isi pakai font sistem (Roboto). Ukuran: judul layar
28, judul seksi 18, nama perangkat 24, isi 15, keterangan 13, label kecil 12.

**Bentuk**: kartu radius 24, hero 32, tombol utama berbentuk pil (tinggi 52–56), chip radius 14, ikon dalam kotak
40×40 radius 14. Padding halaman 16. Jarak antar-kartu 10–14. Target sentuh minimal 48 dp.

## 3. Navigasi

`NavigationBar` dengan 4 tab. Saat belum tersambung, tampilkan `ConnectPage` tanpa tab.

| Tab | Isi (halaman yang sudah ada) |
|---|---|
| **Beranda** | Hero Lokana Cube + nama + chip status; aksi cepat (Cari kunci, Sinkron jam, Layar); Remote (Tap/2×/Tahan dari `ScreenPage`); kisi Studio 2×2 dengan thumbnail OLED mini |
| **Studio** | `SegmentedButton`: Teks · Gambar · Ekspresi · Dadu → `TextPage`, `ImagePage`, `ExpressionPage`, `DicePage` |
| **Terhubung** | Pengingat ketinggalan (`LeavePage`, dengan radar), Notifikasi (`NotifPage`), Cari HP + nada (sekarang ada di Pengaturan, pindahkan ke sini) |
| **Pengaturan** | Kartu Lokana (kecerahan, suara, layar mati, putar 180°, nama BT), Aplikasi (tema, aksen, warna OLED, animasi pembuka), Lainnya (Cara pakai, Tentang) |

Menu titik tiga di Beranda (Putuskan, Lupakan) tetap ada. Ketuk hero membuka `ScreenPage` (layar langsung).

## 4. Komponen baru

- **`LokanaCube`** (CustomPainter, tanpa paket tambahan): gantungan, badan pink bergradasi tipis (PETG
  translusen), jendela OLED gelap, lalu `LokanaEyes` di dalamnya. Parameter: `scale`, `eyeColor` (warna OLED),
  `mood` (idle / mencari / mengantuk / senang). Dipakai di hero, Sambungkan, kartu perangkat di Pengaturan, dan
  daftar perangkat. Ikuti proporsi casing: badan 31,3 × 35 mm, jendela 25 × 13,6 mm.
- **`OledPreview`**: pakai renderer yang ada, tambah grid piksel (garis gelap 1 px tiap piksel saat skala ≥ 2,5×),
  glow tipis, dan label "128×64". Gaya Berjalan/Berkedip dianimasikan di pratinjau.
- **`StudioTile`**: kartu dengan thumbnail OLED mini (dirender asli, bukan ikon), ikon, judul, dan keterangan.
- **`QuickAction`**: ubin tinggi 88. Yang utama pink. Saat aktif ("Hentikan" ketika Cari kunci berbunyi), ikon
  bergetar dan warnanya berganti.
- **`SlotGrid`**: 4 kolom × 2 baris (slot 1–8). Slot terisi menampilkan cuplikan teks dalam font piksel. Slot
  kosong bergaris putus-putus dengan tanda +.
- **Radar ketinggalan**: dua cincin berdenyut di sekitar `LokanaCube` kecil. Kecepatan dan jarak cincin
  mengikuti RSSI (dekat = rapat dan tenang). Kalau terputus, cincin berhenti dan warnanya meredup.

## 5. Gerak dan rasa

- Mata berkedip tiap 3–6 detik secara acak, tidak serempak dengan detik jam.
- Kirim berhasil: haptic ringan (`HapticFeedback.lightImpact`) + mata "senang" 600 ms + snackbar singkat.
  Gagal: haptic `heavyImpact` + pesan dari `Status.describe`.
- Transisi halaman tetap `FadeForwardsPageTransitionsBuilder`. Hormati
  `MediaQuery.disableAnimationsOf(context)`: matikan kedip, radar, dan marquee kalau pengguna meminta.
- Memuat (baca pengaturan atau slot): kerangka abu-abu dengan bentuk kartu, bukan spinner di tengah layar.

## 6. Aturan

- **Tanpa dependensi baru.** Semua bisa dibuat dengan Material 3 bawaan (`NavigationBar`, `SegmentedButton`,
  `Switch`, `Slider`) dan CustomPainter.
- Jangan pakai emoji sebagai ikon UI. Daftar ekspresi yang sekarang berlabel emoji diganti pratinjau mata
  Lokana untuk tiap ekspresi, digambar dengan painter yang sama.
- Teks UI berbahasa Indonesia, kalimat pendek dan ramah. Uji dengan ukuran font sistem 130% tanpa teks terpotong.
- Kontras teks ≥ 4.5:1 (3:1 untuk teks ≥ 24 px) di kedua tema.

## 7. Urutan pengerjaan (satu PR kecil per langkah, uji di HP setiap langkah)

1. Token dan `AppTheme.data()` (warna permukaan, radius, tipografi).
2. Widget `LokanaCube` + mood.
3. Kerangka 4 tab + pemindahan halaman (belum mengubah isi halaman).
4. Beranda.
5. Studio (segmented + `OledPreview` + `SlotGrid`).
6. Terhubung (radar + pindahkan Cari HP).
7. Pengaturan.
8. Sambungkan (mata melirik saat mencari, kartu perangkat).
9. Poles: haptic, kerangka memuat, ekspresi tanpa emoji, cek mode terang, cek font 130%.
