#pragma once
#include <Arduino.h>

// Penyimpanan teks custom (CUSTOM_TEXT). Teks aktif di RAM, slot 1-8 di NVS
// (name tag, pesan favorit). Diisi layanan link / console, dibaca modul Teks.
struct TextMsg {
  uint8_t style = 0;        // 0 diam, 1 berjalan, 2 berkedip
  uint8_t size = 0;         // 0 otomatis, 1-3
  uint16_t durationS = 0;   // 0 = sampai ditutup dengan tombol
  uint8_t font = 0;         // 0 piksel, 1 Sans, 2 Sans Tebal, 3 Serif, 4 Mono Tebal (CUSTOM_TEXT, 0.5.2)
  char text[201] = {0};     // ASCII, maks 200 byte
};

namespace textstore {
constexpr uint8_t SLOTS = 8;
constexpr uint8_t FONTS = 5;
TextMsg& current();
void setCurrent(const TextMsg& m);
bool save(uint8_t slot, const TextMsg& m);   // slot 1..8
bool load(uint8_t slot, TextMsg& out);       // false jika slot kosong
}
