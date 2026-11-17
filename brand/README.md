# Lokana — ikon & aset merek

Ikon resmi aplikasi Lokana: **konsep E, kubus + gantungan**. Bentuknya sama dengan casing Lokana Cube:
badan pink, layar OLED gelap, dua mata, dan lubang gantungan kunci di atas.

Semua file di folder ini dibuat oleh satu skrip dari satu geometri, jadi ukurannya selalu konsisten.
Jangan edit PNG satu per satu. Ubah geometrinya lalu buat ulang semuanya.

| Peran | Warna |
|---|---|
| Latar | `#1A161E` |
| Badan (PETG pink) | `#F478AA` |
| Layar OLED | `#121218` |
| Mata | `#FFFFFF` |

## Isi folder

```
master/    lokana_icon.svg (rounded), lokana_icon_full.svg (persegi penuh), lokana_mark.svg (tanpa latar),
           lokana_icon_1024.png, lokana_mark_512.png (logo transparan untuk halaman Tentang / README)
android/res/
  mipmap-anydpi-v26/ic_launcher.xml, ic_launcher_round.xml   adaptive icon (Android 8+)
  drawable/ic_launcher_foreground.xml                          lapisan depan (vektor, 108dp)
  drawable/ic_launcher_monochrome.xml                          themed icon (Android 13+)
  drawable/ic_stat_lokana.xml                                  ikon notifikasi (siluet putih 24dp)
  values/ic_launcher_background.xml                            warna latar #1A161E
  mipmap-*/ic_launcher.png, ic_launcher_round.png              cadangan Android < 8
tools/gen_icons.py      generator semua file di atas (Pillow)
ios/AppIcon.appiconset/   AppIcon-1024.png (+ versi mode gelap) + Contents.json (format Xcode 14+, satu ukuran)
store/play_store_512.png  ikon Google Play (512×512, persegi penuh; Play membulatkan sendiri)
web/                      favicon.svg/32, apple-touch-icon (180), icon-192/512, icon-maskable-512 (PWA)
```

## Cara pasang

**Android**: salin seluruh isi `brand/android/res/` ke `app/android/app/src/main/res/` dan timpa file lama
(ikon Flutter bawaan dan `ic_stat_lokana.xml` lama). Lalu tambahkan atribut ini di tag `<application>` pada
`AndroidManifest.xml`:

```xml
android:roundIcon="@mipmap/ic_launcher_round"
```

PowerShell (dari folder repo):

```powershell
Copy-Item -Recurse -Force brand\android\res\* app\android\app\src\main\res\
```

Setelah itu `flutter clean`, build ulang, uninstall aplikasi lama di HP, lalu pasang lagi. Launcher sering
menyimpan cache ikon lama.

**iOS** (kalau folder `app/ios/` sudah dibuat dengan `flutter create --platforms=ios .`): ganti
`app/ios/Runner/Assets.xcassets/AppIcon.appiconset/` dengan folder `brand/ios/AppIcon.appiconset/`.

**Web / GitHub Pages**: pakai file di `web/`. `icon-maskable-512.png` diberi `"purpose": "maskable"` di manifest.

## Lisensi

Nama dan logo Lokana adalah **merek dagang**, tidak termasuk lisensi MIT kode maupun CERN-OHL hardware.
Fork boleh memakai kodenya, tapi harus mengganti nama dan ikon.
