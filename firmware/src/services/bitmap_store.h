#pragma once
#include <Arduino.h>

// Penyimpanan gambar 1-bit (BITMAP). Gambar aktif di RAM, slot 1-8 di littlefs
// (/bmp/1.bin ...). Diisi layanan link, dibaca modul Gambar.
struct BitmapMsg {
  static constexpr uint16_t MAX_BYTES = 1024;   // 128x64 layar penuh
  int16_t x = 0, y = 0;
  uint8_t w = 0, h = 0;
  uint16_t durationS = 0;                       // 0 = sampai ditutup dengan tombol
  uint8_t data[MAX_BYTES];
  uint16_t bytes() const { return (uint16_t)((w + 7) / 8) * h; }
  bool empty() const { return !w || !h; }
};

namespace bmpstore {
constexpr uint8_t SLOTS = 8;
bool begin();                                     // mount littlefs (format otomatis jika kosong)
bool ready();
BitmapMsg& current();
bool save(uint8_t slot, const BitmapMsg& m);      // slot 1..8; gambar kosong = hapus slot
bool load(uint8_t slot, BitmapMsg& out);          // false jika slot kosong
}
