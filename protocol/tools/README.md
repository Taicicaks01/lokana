# protocol/tools

## lokana_link.py

Penguji Lokana Link v1 lewat **USB serial**. Satu file, hanya butuh `pyserial`.

```powershell
pip install pyserial
cd lokana\protocol\tools
python lokana_link.py selftest        # cek CRC & contoh byte spesifikasi (tanpa device)
python lokana_link.py test            # uji otomatis semua pesan v0.3 (24 uji)
python lokana_link.py hello           # HELLO -> DEVICE_INFO
python lokana_link.py time            # sinkron jam dari PC
python lokana_link.py text "Halo Wayan" --style scroll --duration 10
python lokana_link.py text "Wayan|KRTI 2026" --slot 1     # simpan name tag ke slot 1
python lokana_link.py expr senang --hold 3000
python lokana_link.py goto jam
python lokana_link.py find --duration 5
python lokana_link.py monitor         # lihat log & frame dari device
```

- Port dipilih otomatis (USB VID `303A`). Kalau ada beberapa board: `--port COM9`.
- **Tutup serial monitor PlatformIO dulu**, karena port hanya bisa dibuka satu program.
- Skrip membuka port dengan DTR/RTS mati lalu menyalakan DTR. Dengan DTR/RTS aktif sejak
  awal, ESP32-C3 bisa tertahan reset dan tidak membalas.

## Menguji BLE

Belum ada skrip BLE dari PC (pairing passkey di Windows sulit diotomatisasi). Pakai
**nRF Connect** di HP:

1. Scan, sambungkan ke `Lokana-XXXX`. OLED menampilkan kode 6 digit; ketik di HP.
2. Service `6c6f6b61-0000-…`: aktifkan notify pada TX (`…0002…`).
3. Tulis ke RX (`…0001…`) dalam format byte array, misalnya HELLO dengan `seq = 1`:
   `00 01 06 00 01 04 03 6E 52 46` (client "nRF") → TX membalas ACK lalu DEVICE_INFO.
4. Ekspresi senang: `22 02 03 00 01 00 00`. Teks "Halo": `30 03 0A 00 00 00 00 00 00 04 48 61 6C 6F`.
