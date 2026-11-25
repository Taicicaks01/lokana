# Lokana Desktop

Aplikasi kecil di **system tray Windows** yang menampilkan kondisi PC di layar Lokana lewat **USB**
(Mode Meja). Versi **0.7.0**, butuh **Lokana OS 0.7.0** atau lebih baru.

Yang dikirim tiap 2 detik (pesan `PC_STATS`, lihat `protocol/LOKANA_LINK.md`):

| Metrik | Sumber | Catatan |
|---|---|---|
| CPU %, RAM % | `psutil` | Selalu ada |
| Suhu CPU | Zona termal Windows (bawaan) atau **LibreHardwareMonitor** | Bawaan: tanpa admin & tanpa program lain (laptop). LibreHardwareMonitor lebih presisi, lihat di bawah |
| Suhu & pemakaian GPU | `nvidia-smi` | Hanya GPU NVIDIA (ikut driver) |
| Unduh, Unggah, Disk | `psutil` | KB/s di bawah 1 MB/s |
| Baterai laptop | `psutil` | Label `Batre+` saat sedang mengisi |

Jam Lokana ikut disinkronkan dengan jam PC saat tersambung (dan tiap jam). Tidak ada angka palsu: sensor yang
tidak tersedia dilewati.

## Pasang

1. Perbarui Lokana ke **Lokana OS 0.7.0** dulu (aplikasi Lokana → Pengaturan → Pembaruan firmware).
2. Unduh `LokanaDesktop.exe` dari [GitHub Releases](https://github.com/Taicicaks01/lokana/releases/latest).
   Tidak perlu instalasi: simpan di folder mana saja (misalnya `Documents\Lokana`) lalu jalankan.
3. Windows SmartScreen mungkin memperingatkan *"Windows protected your PC"* karena aplikasinya belum bertanda tangan
   digital. Pilih **More info → Run anyway**. Kodenya terbuka di folder ini kalau ingin memeriksa.
4. Supaya otomatis jalan: klik kanan ikon tray → **Jalankan saat Windows mulai**.

## Pakai

1. Colok Lokana ke PC lewat USB-C **kanan** (port program) dengan kabel **data** (bukan kabel charge saja).
2. Dalam beberapa detik ikon tray menunjukkan **Tersambung: *nama Lokana* (COMx)** (arahkan kursor ke ikon).
3. Lokana membuka layar **Monitor** sendiri dan layarnya tetap menyala selama data masuk (isi digeser 1 piksel tiap
   2 menit supaya OLED tidak *burn-in*). Di Lokana: **tap** = halaman berikutnya, **tahan** = layar mati, **2× tap**
   = modul lain.
4. Cabut kabel atau pilih **Jeda kirim data**: Lokana kembali ke layar sebelumnya ±10 detik kemudian.

Menu tray (klik kanan): status sambungan, **Pengaturan…**, **Jeda kirim data**, **Jalankan saat Windows mulai**,
**Buka folder log**, **Keluar**.

### Jendela pengaturan (sejak 0.8)

Klik ganda ikon tray (atau menu **Pengaturan…**):

- **Pratinjau OLED 1:1**: gambar layar Monitor persis seperti di Lokana (piksel demi piksel), dengan nilai langsung
  dari PC. Halaman berganti sendiri tiap 5 detik seperti di Lokana; ◀ ▶ = tap.
- **Metrik yang tampil**: centang untuk menampilkan, ↑ ↓ untuk mengurutkan (4 per halaman, maks 12). Nilai langsung
  tampil di samping nama. Metrik yang tidak tersedia di PC ini tampil abu-abu dengan alasannya.
- **Template cepat**: Ringkas, Gamer, Jaringan, Laptop, Semua.
- **Kirim tiap** 1–10 detik.

Semua perubahan langsung dikirim ke Lokana dan **disimpan otomatis** di `config.json` (tanpa tombol Simpan).

### Suhu CPU

**Bawaan (sejak 0.8)**: Lokana Desktop membaca zona termal ACPI dari penghitung kinerja Windows
(*Thermal Zone Information*), tanpa admin dan tanpa program lain. Di laptop zona ini mengikuti suhu CPU/APU (diuji di
Ryzen 5 7535HS: diam ±50 °C, beban penuh ±61 °C, resolusi ±1 °C). Banyak PC desktop tidak punya zona termal ACPI;
di situ baris suhu CPU tidak tampil. Sumber yang dipakai tertulis di jendela pengaturan.

**Lebih presisi (opsional)**: LibreHardwareMonitor membaca sensor CPU langsung (Tctl/Tdie AMD, Package Intel) dan
otomatis dipakai bila berjalan:

1. Unduh **LibreHardwareMonitor** dari [github.com/LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases),
   ekstrak, lalu jalankan `LibreHardwareMonitor.exe` **sebagai administrator** (perlu untuk membaca sensor CPU).
2. Di LibreHardwareMonitor: **Options → Remote Web Server → Run** (port bawaan 8085). Centang juga
   **Options → Start Minimized** dan **Run On Windows Startup** kalau ingin selalu ada.
3. Dalam ±30 detik baris **CPU ..C** muncul di Lokana. Lokana Desktop membaca `http://127.0.0.1:8085/data.json`
   (hanya dari PC sendiri) dan memakai suhu CPU tertinggi (Tctl/Tdie di AMD, Package di Intel).

Suhu GPU NVIDIA tidak butuh LibreHardwareMonitor (dibaca lewat `nvidia-smi` bawaan driver).

## Masalah yang sering muncul

| Gejala | Penyebab | Solusi |
|---|---|---|
| Tray terus **Mencari Lokana...** | Kabel hanya untuk charge, colok di port **bawah** (charger), atau port COM sedang dipegang program lain | Pakai kabel data di port **kanan**. Tutup Arduino IDE / PlatformIO serial monitor / `lokana_link.py`, lalu tunggu ±5 dtk |
| Port COM "Access is denied" / masih dipegang setelah aplikasi ditutup | Proses `LokanaDesktop.exe` lama masih berjalan (mis. ditutup paksa; versi .exe satu-file berjalan sebagai 2 proses) | Task Manager → **Details** → akhiri semua `LokanaDesktop.exe`, lalu jalankan lagi. Selalu tutup lewat menu tray **Keluar** |
| Tray: **Perbarui Lokana OS ke 0.7** | Lokana masih memakai firmware lama (tanpa Monitor PC) | Perbarui firmware lewat aplikasi Lokana |
| Board ESP32 lain (mis. proyek lain) ikut terdeteksi / ingin aman | Lokana dicari di semua port USB ESP32 (VID 303A) dengan pesan `HELLO`; board lain yang tidak membalas dilewati 5 menit | Tambahkan port itu ke `"exclude"` di `config.json` (lihat bawah), atau tetapkan `"port"` Lokana |
| Dua Lokana tercolok | Yang pertama ditemukan yang dipakai | Isi `"port"` di `config.json` |
| Baris suhu CPU tidak ada | PC tanpa zona termal ACPI (umum di PC desktop), dan LibreHardwareMonitor tidak berjalan / bukan administrator / Remote Web Server belum **Run** | Lihat bagian Suhu CPU di atas |
| Baris GPU tidak ada | Bukan GPU NVIDIA, atau driver NVIDIA tanpa `nvidia-smi` | Untuk GPU AMD/Intel belum didukung |
| Antivirus mengkarantina `LokanaDesktop.exe` | Positif palsu umum untuk .exe PyInstaller yang belum bertanda tangan | Pulihkan dari karantina, atau jalankan dari kode (bagian di bawah) |
| Lokana kembali ke wajah walau tray tersambung | **Jeda kirim data** tercentang | Hilangkan centangnya |

Pengaturan di `%APPDATA%\LokanaDesktop\config.json` (dibuat otomatis saat pertama jalan):

```json
{ "port": null, "exclude": ["COM7"], "interval": 2, "metrics": ["cpu", "ram", "cpu_temp", "gpu_temp"] }
```

`port` = paksa port tertentu (contoh `"COM10"`), `exclude` = port yang tidak boleh dicoba sama sekali,
`interval` = detik antar kirim (1–10), `metrics` = metrik yang tampil, berurutan (`cpu`, `ram`, `cpu_temp`, `gpu_temp`,
`gpu`, `down`, `up`, `disk`, `battery`; diatur dari jendela pengaturan). Log: `%APPDATA%\LokanaDesktop\log.txt` (menu **Buka folder log**).
Port dibuka tanpa DTR/RTS sehingga board tidak ter-reset.

## Dari kode

```bat
cd desktop
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt -r requirements-build.txt
.venv\Scripts\python lokana_desktop.py              :: tray
.venv\Scripts\python lokana_desktop.py --no-tray    :: tanpa tray, metrik dicetak ke terminal
.venv\Scripts\python lokana_desktop.py --settings   :: tray + langsung buka jendela pengaturan
.venv\Scripts\python oled_preview.py --compare COM10 :: cek pratinjau = layar Lokana asli (harus 0 piksel beda)
build.bat                                           :: dist\LokanaDesktop.exe (PyInstaller, satu file)
```

Kode protokol (frame, CRC, payload) dipakai ulang dari `protocol/tools/lokana_link.py`.

| Berkas | Isi |
|---|---|
| `lokana_desktop.py` | Tray, pengaturan, mulai bersama Windows (`HKCU\...\Run`), pekerja kirim metrik |
| `link_usb.py` | Cari Lokana (HELLO → DEVICE_INFO), sambung ulang, TIME_SYNC, PC_STATS |
| `sensors.py` | psutil, nvidia-smi, LibreHardwareMonitor; daftar metrik ber-ID + template |
| `settings_window.py` | Jendela pengaturan (tkinter bawaan Python) |
| `oled_preview.py` | Render modul Monitor 128×64 di PC, port dari `firmware/src/modules/monitor_module.cpp`. **Kalau tata letak Monitor di firmware berubah, ubah juga file ini** lalu jalankan `--compare` |
| `oled_font.py` | Font piksel 5×7 Lokana (Adafruit GFX `glcdfont.c`, BSD), dibuat `tools/gen_oled_font.py` |
| `build.bat` | PyInstaller → `dist\LokanaDesktop.exe` |

Rencana berikutnya (v0.8): kirim lewat WiFi UDP (tanpa kabel data), mDNS untuk menemukan Lokana.
