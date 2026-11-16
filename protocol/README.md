# protocol

Spesifikasi **Lokana Link**, satu format pesan untuk semua komunikasi dengan Lokana
(BLE ke aplikasi HP, USB serial dan WiFi UDP ke Lokana Desktop).

| Dokumen | Isi |
|---|---|
| [LOKANA_LINK.md](LOKANA_LINK.md) | Spesifikasi lengkap v1: frame, transport, daftar pesan, keamanan, contoh byte |

Implementasi yang mengikuti spesifikasi ini:

| Bagian | Lokasi | Status |
|---|---|---|
| Firmware (parser + BLE + USB) | `firmware/src/services/link*` | ✅ v0.3 (pesan v0.3) |
| Skrip uji Python | [`tools/lokana_link.py`](tools/lokana_link.py) | ✅ v0.3 (USB) |
| Aplikasi Android | `app/` | 📋 v0.4 |
| Lokana Desktop | `desktop/` | 📋 v0.7 |
