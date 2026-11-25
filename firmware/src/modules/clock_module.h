#pragma once
#include "core/module.h"
#include "config.h"

// Jam dengan 4 gaya (SETTINGS clock_style, 0.8; menu "Gaya jam"):
//   Klasik  angka yang berubah meluncur ke atas (bawaan)
//   Mata    mata Lokana melirik mengikuti detik; saat menit berganti melirik ke atas menjemput angka baru
//   Kubus   angka tersusun dari kubus 4x4; saat menit berganti kubus lama jatuh, kubus baru jatuh & menumpuk
//   Kedip   angka besar yang sesekali berkedip; saat menit berganti angka memejam lalu membuka sebagai angka baru
// Tap = mode detik (semua gaya). 128x32 selalu Klasik. Console `jam anim` memutar animasi ganti menit (uji).
class ClockModule : public Module {
public:
  const char* name() const override { return "Jam"; }
  void enter() override;
  bool input(Gesture g) override;
  void render(Adafruit_GFX& g, uint32_t now) override;
  bool drawsBattery() const override { return SCREEN_H >= 64; }

  static void demoAnim();          // console: putar animasi ganti menit sekarang (menit sebelumnya -> sekarang)

private:
  void drawDigits(Adafruit_GFX& g, float p, uint32_t now);
  void drawFooter(Adafruit_GFX& g, const struct tm& t, uint32_t now, bool bar);
  void renderEyes(Adafruit_GFX& g, const struct tm& t, uint32_t now);
  void renderCubes(Adafruit_GFX& g, const struct tm& t, uint32_t now);
  void renderBlink(Adafruit_GFX& g, const struct tm& t, uint32_t now);
  char _shown[6] = "--:--";
  char _prev[6] = "--:--";
  uint32_t _animAt = 0;
  uint8_t _style = 255;
  bool _seconds = false;
  // Mata: lirikan halus, kedip acak
  float _lookX = 0, _lookY = 0;
  uint32_t _blinkAt = 0, _nextBlink = 0;
  // Kedip: angka yang berkedip sendiri
  uint8_t _blinkDigit = 0;
};
