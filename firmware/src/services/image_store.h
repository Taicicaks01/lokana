#pragma once
#include <Arduino.h>

// Galeri gambar & animasi 1-bit (BITMAP, ANIM). Gambar diam = animasi 1 bingkai.
// Slot 1-8 di littlefs (/img/N.bin), "sekarang" (slot 0) hanya di RAM.
// Data bingkai di heap; Anim tidak boleh disalin, hanya dipindah dengan swap().
struct Anim {
  static constexpr uint32_t MAX_BYTES = 16384;   // 16 bingkai layar penuh
  static constexpr uint8_t MAX_FRAMES = 32;
  uint8_t frames = 0, loops = 0, w = 0, h = 0;
  uint16_t frameMs = 100, durationS = 0;
  int16_t x = 0, y = 0;
  uint8_t* data = nullptr;

  Anim() = default;
  ~Anim() { release(); }
  Anim(const Anim&) = delete;
  Anim& operator=(const Anim&) = delete;

  uint16_t frameBytes() const { return (uint16_t)((w + 7) / 8) * h; }
  uint32_t totalBytes() const { return (uint32_t)frameBytes() * frames; }
  bool empty() const { return !data || !frames || !w || !h; }
  uint8_t* frame(uint8_t i) const { return data + (uint32_t)i * frameBytes(); }
  bool alloc();                 // siapkan data sesuai frames/w/h (diisi nol); false jika terlalu besar
  void release();
  void swap(Anim& o);
};

namespace imgstore {
constexpr uint8_t SLOTS = 8;
bool begin();                   // mount littlefs (format otomatis jika kosong)
bool ready();
Anim& current();                // animasi "tampilkan sekarang"
bool save(uint8_t slot, const Anim& a);
bool load(uint8_t slot, Anim& out, bool firstOnly = false);
bool remove(uint8_t slot);
bool info(uint8_t slot, uint8_t& frames, uint8_t& w, uint8_t& h);   // false jika kosong
}
