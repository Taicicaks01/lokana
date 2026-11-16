# Aplikasi Lokana (Android)

Aplikasi pendamping Lokana: sambungkan lewat BLE, lalu kirim ekspresi, teks, emoji/gambar,
lempar dadu, cari kunci, ubah pengaturan, dan dipanggil Lokana saat HP terselip (Cari HP).

Versi **0.4.0** (MVP). Android dulu; iOS menyusul (lihat `docs/ARCHITECTURE.md` §4).

## Arsitektur

| Bagian | Lokasi | Tugas |
|---|---|---|
| UI | `lib/` (Flutter) | Layar sambung, dasbor, ekspresi, teks, emoji & gambar, dadu, pengaturan |
| Codec payload | `lib/link/proto.dart` | Encode/decode payload Lokana Link (diuji di `test/proto_test.dart`) |
| Jembatan | `lib/link/link.dart` ↔ `MainActivity.kt` | MethodChannel `lokana/link`, EventChannel `lokana/events` |
| BLE + framing | `android/.../BleLink.kt` | Scan, connect, MTU 247, bonding, notify, antrean tulis, `seq`/ACK/kirim ulang |
| Layanan latar | `android/.../LinkService.kt` | *Foreground service* (connectedDevice) menjaga koneksi saat aplikasi ditutup |
| Cari HP | `android/.../Alarm.kt` | Bunyi alarm (tetap terdengar saat senyap) + getar + notifikasi "Ketemu" |

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

## Alur sambung

1. **Cari** → pilih `Lokana-XXXX`. Lokana meminta keamanan begitu tersambung.
2. HP baru: Android menampilkan dialog pairing. Ketik kode 6 digit dari layar Lokana.
3. Setelah terenkripsi, aplikasi otomatis mengirim `HELLO`, `TIME_SYNC`, dan `SETTINGS GET`.
4. Koneksi terputus → Android menyambung ulang sendiri saat Lokana kembali dalam jangkauan.
   **Putuskan** di menu dasbor menghentikannya; **Putuskan & lupakan** juga menghapus Lokana
   terakhir dari aplikasi (pairing di Android dihapus dari pengaturan Bluetooth HP).
