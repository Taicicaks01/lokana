# Lokana Desktop

Aplikasi kecil di **system tray Windows** yang menampilkan kondisi PC di layar Lokana lewat **USB**
(Mode Meja). Versi **0.7.0**, butuh **Lokana OS 0.7** atau lebih baru.

Yang dikirim tiap 2 detik (pesan `PC_STATS`, lihat `protocol/LOKANA_LINK.md`):

| Metrik | Sumber | Catatan |
|---|---|---|
| CPU %, RAM % | `psutil` | Selalu ada |
| Suhu CPU | **LibreHardwareMonitor** | Opsional, lihat di bawah. Tanpa itu baris ini tidak tampil |
| Suhu & pemakaian GPU | `nvidia-smi` | Hanya GPU NVIDIA (ikut driver) |
| Unduh, Unggah, Disk | `psutil` | KB/s di bawah 1 MB/s |
| Baterai laptop | `psutil` | Label `Batre+` saat sedang mengisi |

Jam Lokana ikut disinkronkan dengan jam PC saat tersambung (dan tiap jam). Tidak ada angka palsu: sensor yang
tidak tersedia dilewati.

## Pakai

1. Colok Lokana ke PC lewat USB-C **kanan** (port program).
2. Jalankan `LokanaDesktop.exe` (dari GitHub Releases). Ikon Lokana muncul di system tray.
3. Lokana membuka layar **Monitor** sendiri; tap = halaman berikutnya, tahan = layar mati.

Menu tray: status sambungan, **Jeda kirim data**, **Jalankan saat Windows mulai**, **Buka folder log**, **Keluar**.

Lokana dicari otomatis di semua port USB ESP32 (VID 303A) dengan pesan `HELLO`; hanya yang membalas sebagai
Lokana yang dipakai. Port lain (mis. board ESP32 lain) dilewati 5 menit. Port dibuka tanpa DTR/RTS sehingga board
tidak ter-reset. Pengaturan di `%APPDATA%\LokanaDesktop\config.json`:

```json
{ "port": null, "exclude": ["COM7"], "interval": 2 }
```

`port` = paksa port tertentu, `exclude` = port yang tidak boleh dicoba sama sekali, `interval` = detik antar kirim.
Log: `%APPDATA%\LokanaDesktop\log.txt`.

### Suhu CPU (opsional)

Windows tidak menyediakan suhu CPU untuk aplikasi biasa. Pasang **LibreHardwareMonitor**, jalankan sebagai
administrator, lalu aktifkan **Options → Remote Web Server → Run** (port 8085). Lokana Desktop membaca
`http://127.0.0.1:8085/data.json` (hanya dari PC sendiri) dan memakai suhu CPU tertinggi (Tctl/Tdie / Package).

## Dari kode

```bat
cd desktop
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt -r requirements-build.txt
.venv\Scripts\python lokana_desktop.py              :: tray
.venv\Scripts\python lokana_desktop.py --no-tray    :: tanpa tray, metrik dicetak ke terminal
build.bat                                           :: dist\LokanaDesktop.exe (PyInstaller, satu file)
```

Kode protokol (frame, CRC, payload) dipakai ulang dari `protocol/tools/lokana_link.py`.

| Berkas | Isi |
|---|---|
| `lokana_desktop.py` | Tray, pengaturan, mulai bersama Windows (`HKCU\...\Run`), pekerja kirim metrik |
| `link_usb.py` | Cari Lokana (HELLO → DEVICE_INFO), sambung ulang, TIME_SYNC, PC_STATS |
| `sensors.py` | psutil, nvidia-smi, LibreHardwareMonitor |
| `build.bat` | PyInstaller → `dist\LokanaDesktop.exe` |

Rencana berikutnya (v0.8): kirim lewat WiFi UDP (tanpa kabel data), mDNS untuk menemukan Lokana.
