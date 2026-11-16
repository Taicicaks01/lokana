#pragma once
#include "core/module.h"

// Jam animasi: angka yang berubah meluncur ke atas. Tap = tampilkan detik.
// 128x64: digit besar + baris tanggal + bilah detik.
class ClockModule : public Module {
public:
  const char* name() const override { return "Jam"; }
  void enter() override;
  bool input(Gesture g) override;
  void render(Adafruit_GFX& g, uint32_t now) override;

private:
  void drawDigits(Adafruit_GFX& g, float p, uint32_t now);
  char _shown[6] = "--:--";
  char _prev[6] = "--:--";
  uint32_t _animAt = 0;
  bool _seconds = false;
};
