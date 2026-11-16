# protocol/tools

## lokana_link.py

Penguji Lokana Link v1 lewat **USB serial**. Satu file, hanya butuh `pyserial`
(`--image` di perintah `bitmap` butuh `pillow`).

```powershell
pip install pyserial
cd lokana\protocol\tools
python lokana_link.py selftest        # cek CRC & contoh byte spesifikasi (tanpa device)
python lokana_link.py test            # uji otomatis pesan v0.3 - v0.5.3
python lokana_link.py test --touch    # + uji BUTTON (sentuh Lokana saat diminta)
python lokana_link.py hello           # HELLO -> DEVICE_INFO
python lokana_link.py time            # sinkron jam dari PC
python lokana_link.py text "Halo Wayan" --style scroll --duration 10
python lokana_link.py text "Wayan|KRTI 2026" --slot 1     # simpan name tag ke slot 1
python lokana_link.py text "Halo!" --font sans-tebal     # font: piksel sans sans-tebal serif mono-tebal (0.5.2)
python lokana_link.py settings --notif-popup 10          # lama popup notifikasi, 0 = tidak muncul
python lokana_link.py settings --boot-guide off          # Panduan setelah splash boot (0.5.3)
python lokana_link.py textslots                          # isi slot teks 1-8 (TEXT_SLOT, 0.5.3)
python lokana_link.py textslots --show 1 --duration 5    # tampilkan slot 1 sekarang
python lokana_link.py expr senang --hold 3000
python lokana_link.py goto jam
python lokana_link.py find --duration 5
python lokana_link.py settings        # baca pengaturan
python lokana_link.py settings --brightness 2 --timeout 60 --name "Lokana Wayan"
python lokana_link.py dice d20        # lempar dadu, tunggu hasilnya
python lokana_link.py bitmap --demo hati --slot 1            # senyum / hati / catur
python lokana_link.py bitmap --image logo.png --duration 10  # file gambar, diperkecil ke 128x64
python lokana_link.py listen          # dengarkan hasil dadu, BUTTON, FIND_PHONE
python lokana_link.py notif WhatsApp "Ibu" "Sudah makan?" --important
python lokana_link.py notif --delete 1
python lokana_link.py call "Ibu"      # panggilan masuk;  call --stop  untuk selesai
python lokana_link.py anim --demo bola --slot 2               # animasi: bola / denyut / kedip
python lokana_link.py anim --gif kucing.gif --duration 10     # GIF -> animasi (butuh pillow)
python lokana_link.py gallery         # isi galeri slot 1-8 sebagai gambar teks
python lokana_link.py screen          # layar Lokana langsung di terminal (Ctrl+C keluar)
python lokana_link.py screen --shot layar.png                # screenshot untuk dokumentasi (pillow)
python lokana_link.py press double    # gestur jarak jauh: tap / double / triple / tahan
python lokana_link.py settings --name "Lokana_लोचन-01"       # nama Bluetooth
python lokana_link.py monitor         # lihat log & frame dari device
```

- Port dipilih otomatis (USB VID `303A`). Kalau ada beberapa board: `--port COM9`.
- **Tutup serial monitor PlatformIO dulu**, karena port hanya bisa dibuka satu program.
- Skrip membuka port dengan DTR/RTS mati lalu menyalakan DTR. Dengan DTR/RTS aktif sejak
  awal, ESP32-C3 bisa tertahan reset dan tidak membalas.
- Pesan dari device tanpa diminta (hasil dadu, BUTTON, FIND_PHONE) hanya dikirim lewat USB
  setelah `HELLO`, dan berhenti begitu ada perintah console. Karena itu `test` menguji console
  paling akhir, dan BUTTON perlu sentuhan sungguhan (`--touch`), bukan perintah `tap`.

## Menguji BLE

Belum ada skrip BLE dari PC (pairing passkey di Windows sulit diotomatisasi). Pakai
**nRF Connect** di HP:

1. Scan, sambungkan ke `Lokana-XXXX`. OLED menampilkan kode 6 digit; ketik di HP.
2. Service `6c6f6b61-0000-…`: aktifkan notify pada TX (`…0002…`).
3. Tulis ke RX (`…0001…`) dalam format byte array, misalnya HELLO dengan `seq = 1`:
   `00 01 06 00 01 04 03 6E 52 46` (client "nRF") → TX membalas ACK lalu DEVICE_INFO.
4. Ekspresi senang: `22 02 03 00 01 00 00`. Teks "Halo": `30 03 0A 00 00 00 00 00 00 04 48 61 6C 6F`.
