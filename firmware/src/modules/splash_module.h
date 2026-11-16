#pragma once
#include "core/module.h"
#include "core/face.h"

// Splash boot: garis atas (shirorekha) tumbuh, huruf लोचन turun dari garis, matra ो muncul,
// "LOKANA" mengetik, kilau melintas, lalu tulisan kembali ke garis yang terbelah menjadi
// dua mata terpejam -> wajah Lokana membuka mata. Tap = lewati.
// Uji: console `splash` (putar ulang) atau `splash <ms>` (bekukan di detik tertentu untuk screenshot).
class SplashModule : public Module {
public:
  explicit SplashModule(Face& face) : _face(face) {}
  const char* name() const override { return "Splash"; }
  void enter() override;
  bool input(Gesture g) override;
  void event(const Event& e) override;
  void update(uint32_t now) override;
  void render(Adafruit_GFX& g, uint32_t now) override;
  bool keepAwake() const override { return true; }
  bool hidden() const override { return true; }

private:
  uint32_t elapsed(uint32_t now) const;
  void finish();
  Face& _face;
  uint32_t _t0 = 0, _freeze = 0;
  uint8_t _sfx = 0;
};
