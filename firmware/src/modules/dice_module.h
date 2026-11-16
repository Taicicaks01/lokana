#pragma once
#include "core/module.h"

// Dadu digital: 1d6, 2d6, d4, d8, d10, d12, d20, koin.
// Tap = lempar, tahan = ganti jenis dadu. Angka acak dari hardware RNG ESP32-C3.
class DiceModule : public Module {
public:
  const char* name() const override { return "Dadu"; }
  bool input(Gesture g) override;
  void event(const Event& e) override;
  void update(uint32_t now) override;
  void render(Adafruit_GFX& g, uint32_t now) override;
  bool keepAwake() const override { return _rolling; }

private:
  void roll();
  void finish();
  uint8_t sides() const;
  void drawD6(Adafruit_GFX& g, int x, int y, int s, uint8_t v);

  uint8_t _type = 0;
  uint8_t _a = 0, _b = 0;          // hasil (0 = belum dilempar)
  bool _rolling = false;
  uint32_t _rollAt = 0, _nextFlip = 0;
  uint16_t _step = 40;
};
