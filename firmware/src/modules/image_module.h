#pragma once
#include "core/module.h"
#include "services/image_store.h"

// Gambar & animasi 1-bit dari aplikasi (BITMAP / ANIM).
// Gambar masuk: tampil sampai durasi habis atau tap -> kembali ke modul sebelumnya.
// Dibuka lewat double-tap: galeri slot 1-8, tap = slot berikutnya.
class ImageModule : public Module {
public:
  const char* name() const override { return "Gambar"; }
  void enter() override;
  void exit() override;
  bool input(Gesture g) override;
  void event(const Event& e) override;
  void update(uint32_t now) override;
  void render(Adafruit_GFX& g, uint32_t now) override;
  bool keepAwake() const override { return _incoming; }

private:
  bool nextSlot();
  Anim _img;                        // bingkai di heap (maks 16 KB)
  bool _incoming = false;
  uint8_t _slot = 0;                // slot yang tampil (0 = gambar masuk)
  uint32_t _shownAt = 0, _labelUntil = 0;
};
