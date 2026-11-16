#pragma once
#include "core/module.h"

// Panduan cara pakai: kartu bergantian (Hai -> TAP -> 2x TAP -> 3x TAP -> TAHAN -> aplikasi),
// tiap gestur diperagakan dengan animasi jari di sensor sentuh. Diputar setelah splash boot
// (SETTINGS boot_guide / menu Panduan > Saat boot), dari menu Panduan > Putar sekarang,
// atau GOTO "Panduan". Sentuhan apa pun = lewati. Uji: console `guide [ms]`.
class GuideModule : public Module {
public:
  const char* name() const override { return "Panduan"; }
  void enter() override;
  bool input(Gesture g) override;
  void event(const Event& e) override;
  void update(uint32_t now) override;
  void render(Adafruit_GFX& g, uint32_t now) override;
  bool keepAwake() const override { return true; }
  bool hidden() const override { return true; }
  bool remoteOpen() const override { return true; }

  static const uint8_t CARDS = 6;
  static const uint32_t CARD_MS = 2800;

private:
  uint32_t elapsed(uint32_t now) const { return _freeze ? _freeze : now - _t0; }
  void finish();
  uint32_t _t0 = 0, _freeze = 0;
};
