#pragma once
#include "core/module.h"
#include "services/bitmap_store.h"

// Gambar/emoji 1-bit dari aplikasi (BITMAP).
// Gambar masuk: tampil sampai durasi habis atau tap -> kembali ke modul sebelumnya.
// Dibuka lewat double-tap: tap = ganti gambar tersimpan (slot 1-8).
class ImageModule : public Module {
public:
  const char* name() const override { return "Gambar"; }
  void enter() override;
  bool input(Gesture g) override;
  void event(const Event& e) override;
  void update(uint32_t now) override;
  void render(Adafruit_GFX& g, uint32_t now) override;
  bool keepAwake() const override { return _incoming; }

private:
  bool nextSlot();
  BitmapMsg _img;                   // 1 KB
  bool _incoming = false, _have = false;
  int8_t _slot = 0;                 // 0 = gambar terakhir dari aplikasi, 1..8 = slot
  uint32_t _shownAt = 0;
};
