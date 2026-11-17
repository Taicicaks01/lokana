#pragma once
#include "core/module.h"

// Layar pembaruan firmware (OTA): versi, bar progres, lalu "Memasang ulang". Dibuka oleh EV_OTA.
// Data dari services/ota; modul ini hanya menampilkan. Sentuhan tidak membatalkan (batal dari aplikasi).
class UpdateModule : public Module {
public:
  const char* name() const override { return "Update"; }
  bool hidden() const override { return true; }
  bool input(Gesture g) override { (void)g; return true; }
  void event(const Event& e) override;
  void update(uint32_t now) override;
  void render(Adafruit_GFX& g, uint32_t now) override;
  bool keepAwake() const override { return true; }

private:
  uint32_t _doneAt = 0;
};
