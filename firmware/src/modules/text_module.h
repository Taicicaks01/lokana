#pragma once
#include "core/module.h"
#include <gfxfont.h>
#include "services/text_store.h"

// Teks custom dari aplikasi (CUSTOM_TEXT): diam, berjalan, atau berkedip.
// Pesan masuk: tampil sampai durasi habis atau tap -> kembali ke modul sebelumnya.
// Dibuka lewat double-tap: tap = ganti slot tersimpan (name tag, pesan favorit).
class TextModule : public Module {
public:
  const char* name() const override { return "Teks"; }
  void enter() override;
  bool input(Gesture g) override;
  void event(const Event& e) override;
  void update(uint32_t now) override;
  void render(Adafruit_GFX& g, uint32_t now) override;
  bool keepAwake() const override { return _incoming; }

private:
  struct Line { uint8_t start, len; };
  // Font aktif: f = nullptr -> font piksel bawaan dengan skala `scale`
  struct Metrics { const GFXfont* f; uint8_t scale; int lineH, asc; };
  static Metrics metrics(uint8_t font, uint8_t size);
  static int charW(const Metrics& m, char c);
  int textW(const char* s, int n) const;
  void draw(Adafruit_GFX& g, uint32_t t);
  static constexpr uint8_t MAX_LINES = 28;
  void show(const TextMsg& m);
  void layout();
  bool nextSlot();

  TextMsg _msg;
  bool _incoming = false, _empty = true, _vscroll = false;
  int8_t _slot = 0;                 // 0 = teks terakhir dari aplikasi, 1..8 = slot tersimpan
  uint32_t _shownAt = 0;
  Line _lines[MAX_LINES];
  uint8_t _n = 0;
  Metrics _m{nullptr, 1, 8, 7};
};
