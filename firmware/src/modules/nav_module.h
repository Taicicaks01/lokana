#pragma once
#include "core/module.h"

// Navigasi Google Maps (NAV, v0.6): panah belokan, jarak, instruksi, jalan, waktu tiba.
// Hanya ikut giliran double-tap selama navigasi berjalan. Layar menyala sendiri saat navigasi mulai,
// instruksi baru, atau tinggal < 300 m ke belokan (lalu tetap menyala sampai belokan lewat);
// di luar itu layar ikut batas waktu biasa (keputusan Wayan 2026-11-21, hemat baterai).
class NavModule : public Module {
public:
  const char* name() const override { return "Navigasi"; }
  bool available() const override;
  void event(const Event& e) override;
  void render(Adafruit_GFX& g, uint32_t now) override;
  bool keepAwake() const override;
  bool drawsBattery() const override { return true; }   // layar penuh: tanpa lencana baterai / DEV
};
