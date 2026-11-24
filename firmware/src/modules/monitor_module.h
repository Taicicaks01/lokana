#pragma once
#include "core/module.h"

// Monitor PC (PC_STATS, v0.7, Mode Meja): metrik dari Lokana Desktop, 4 per halaman (128x64).
// Hanya ikut giliran double-tap selama data masuk. Layar tetap menyala selama data masuk (dapat daya USB);
// isi digeser 1 px tiap 2 menit supaya OLED tidak burn-in (keputusan Wayan 2026-11-25).
// Tap = halaman berikutnya; halaman juga berganti sendiri tiap 5 dtk. Tahan = layar mati seperti biasa.
class MonitorModule : public Module {
public:
  const char* name() const override { return "Monitor"; }
  bool available() const override;
  void enter() override;
  bool input(Gesture g) override;
  void event(const Event& e) override;
  void render(Adafruit_GFX& g, uint32_t now) override;
  bool keepAwake() const override;
  bool drawsBattery() const override { return true; }   // layar penuh: tanpa lencana

private:
  uint8_t _page = 0;
  uint32_t _pageAt = 0;
};
