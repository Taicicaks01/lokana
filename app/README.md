# Aplikasi Lokana (Android)

Aplikasi pendamping Lokana: sambungkan lewat BLE, lalu kirim ekspresi, teks, emoji/gambar,
lempar dadu, cari kunci, ubah pengaturan, dan dipanggil Lokana saat HP terselip (Cari HP).
Sejak 0.5.0 juga meneruskan **notifikasi** aplikasi pilihan dan **panggilan masuk**.

Versi **0.5.0**. Android dulu; iOS menyusul (lihat `docs/ARCHITECTURE.md` §4).

## Arsitektur

| Bagian | Lokasi | Tugas |
|---|---|---|
| UI | `lib/` (Flutter) | Layar sambung, dasbor, ekspresi, teks, emoji & gambar, dadu, pengaturan |
| Codec payload | `lib/link/proto.dart` | Encode/decode payload Lokana Link (diuji di `test/proto_test.dart`) |
| Jembatan | `lib/link/link.dart` ↔ `MainActivity.kt` | MethodChannel `lokana/link`, EventChannel `lokana/events` |
| BLE + framing | `android/.../BleLink.kt` | Scan, connect, MTU 247, bonding, notify, antrean tulis, `seq`/ACK/kirim ulang |
| Layanan latar | `android/.../LinkService.kt` | *Foreground service* (connectedDevice) menjaga koneksi saat aplikasi ditutup |
| Cari HP | `android/.../Alarm.kt` | Bunyi alarm (tetap terdengar saat senyap) + getar + notifikasi "Ketemu" |
| Notifikasi | `android/.../NotifListener.kt`, `NotifPrefs.kt` | *NotificationListener*: aplikasi pilihan → `NOTIF`, panggilan (CallStyle) → `CALL` |

BLE ditulis langsung di Kotlin, **tanpa plugin BLE pihak ketiga**: `flutter_blue_plus` 2.x
tidak lagi berlisensi BSD (lisensi berbayar untuk perusahaan ≥ 15 orang, dan *ping* ke server
pembuatnya setiap build). Koneksi di Kotlin juga dibutuhkan untuk v0.5 (NotificationListener
mengirim notifikasi langsung tanpa menunggu UI Flutter).

Kode paket: `io.github.taicicaks01.lokana`. Tidak ada dependensi Dart selain Flutter SDK.

## Build & pasang

Butuh Flutter (stable), JDK 17+, dan Android SDK.

```powershell
cd lokana\app
flutter pub get
flutter test                 # uji codec Lokana Link
flutter build apk --release --split-per-abi   # HP modern: build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
flutter install              # pasang ke HP yang tersambung USB (USB debugging aktif)
```

Build rilis saat ini ditandatangani dengan *debug key* (cukup untuk uji). Kunci rilis untuk
Play Store disiapkan sebelum rilis resmi.

## Izin Android

| Izin | Untuk |
|---|---|
| `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` (Android 12+) | Mencari & menyambung ke Lokana. Scan tidak dipakai untuk lokasi |
| `ACCESS_FINE_LOCATION` (Android 11 ke bawah) | Syarat Android lama untuk scan BLE |
| `POST_NOTIFICATIONS` (Android 13+) | Notifikasi koneksi & tombol "Ketemu" saat Cari HP (boleh ditolak) |
| `FOREGROUND_SERVICE_CONNECTED_DEVICE` | Menjaga koneksi BLE di latar belakang |
| `VIBRATE` | Getar saat Cari HP |
| Akses notifikasi (diaktifkan di Pengaturan Android) | Membaca notifikasi aplikasi yang dipilih |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Tombol "Izinkan berjalan di latar" supaya koneksi tidak diputus penghemat baterai |

## Pairing, lupakan, nama

- **Lupakan Lokana ini** (menu dasbor) menghapus pairing di **dua sisi**: aplikasi mengirim `UNPAIR`
  ke Lokana, lalu menghapus *bond* di HP. Sambungan berikutnya meminta kode 6 digit baru.
- Jika Lokana sudah melupakan HP (menu Lokana → Lupakan HP) tetapi HP masih menyimpan pairing lama,
  aplikasi mendeteksinya (koneksi diputus Lokana sebelum siap), menghapus pairing lama, lalu pairing
  ulang otomatis. Jika HP menolak, muncul tombol **Buka Pengaturan Bluetooth**.
- **Nama Bluetooth** diganti di Pengaturan (UTF-8, maks 26 byte, boleh Dewanagari).

## Emoji & Gambar

Emoji/teks digambar HP lalu **dipotong rapat** ke piksel yang terisi (tidak terpotong lagi), diberi efek
(Diam, Denyut, Memantul, Goyang, Putar, Kedip, Geser), atau ambil **gambar/GIF** dari HP (dithering untuk
foto, maks 16 bingkai layar penuh). Galeri menampilkan isi slot 1–8 langsung dari Lokana.

## Layar Lokana & tema

- **Layar Lokana** (dasbor): isi OLED tampil langsung di HP (`SCREEN`, dikirim hanya saat berubah,
  maks 10 fps), tombol remote Tap/Double/Triple/Tahan, dan screenshot PNG 4x ke Galeri (Pictures/Lokana).
- **Pengaturan → Tampilan aplikasi**: tema Sistem/Terang/Gelap, 7 warna aksen, dan warna piksel pratinjau
  (biru muda, putih, kuning, hijau) sesuai OLED yang dipakai. Disimpan di HP, bisa diubah walau belum tersambung.

## Notifikasi & panggilan

- Hanya aplikasi yang **dicentang** di halaman Notifikasi yang diteruskan (pertama kali: aplikasi
  pesan/email populer yang terpasang). Yang dikirim hanya nama aplikasi, judul, dan maks 160 karakter isi.
- Notifikasi *ongoing* (musik, unduhan, layanan) dan ringkasan grup dilewati; isi yang sama tidak
  dikirim dua kali. Notifikasi dihapus di HP → ikut dihapus di Lokana.
- Huruf beraksen diubah ke ASCII dan emoji dibuang (font OLED hanya ASCII).
- Panggilan masuk dibaca dari notifikasi panggilan (telepon biasa & WhatsApp), **tanpa izin telepon**.
- Membuka aplikasi, atau Android menghidupkan ulang layanan notifikasi, otomatis menyambung lagi ke
  Lokana terakhir (kecuali pengguna menekan **Putuskan**).

## Alur sambung

1. **Cari** → pilih `Lokana-XXXX`. Lokana meminta keamanan begitu tersambung.
2. HP baru: Android menampilkan dialog pairing. Ketik kode 6 digit dari layar Lokana.
3. Setelah terenkripsi, aplikasi otomatis mengirim `HELLO`, `TIME_SYNC`, dan `SETTINGS GET`.
4. Koneksi terputus → Android menyambung ulang sendiri saat Lokana kembali dalam jangkauan.
   **Putuskan** di menu dasbor menghentikannya; **Putuskan & lupakan** juga menghapus Lokana
   terakhir dari aplikasi (pairing di Android dihapus dari pengaturan Bluetooth HP).
