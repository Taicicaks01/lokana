#pragma once
#include "core/module.h"

// Pengingat ketinggalan (SETTINGS leave_alert): HP yang tersambung tiba-tiba hilang (sinyal melemah lalu putus)
// dan tidak kembali dalam 20 detik -> layar "HP-mu tertinggal?" + bunyi 30 detik. Keputusan ada di layanan link;
// modul ini hanya menampilkan. Tap = diam & tutup. HP tersambung lagi = tutup sendiri.
// Uji: console `left` / `left 0`, atau GOTO "Tertinggal".
class LeftModule : public Module {
public:
  const char* name() const override { return "Tertinggal"; }
  void enter() override;
  void exit() override;
  bool input(Gesture g) override;
  void event(const Event& e) override;
  void update(uint32_t now) override;
  void render(Adafruit_GFX& g, uint32_t now) override;
  bool keepAwake() const override { return true; }
  bool hidden() const override { return true; }
  bool remoteOpen() const override { return true; }

private:
  void close(const char* msg);
  uint32_t _since = 0;
  bool _ringing = false;
};
