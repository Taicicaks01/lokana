#pragma once
#include "core/module.h"

// Notifikasi HP (NOTIF). Notifikasi baru muncul sebentar lalu kembali ke modul sebelumnya.
// Dibuka lewat double-tap: tap = notifikasi berikutnya, tahan = hapus yang tampil.
class NotifModule : public Module {
public:
  const char* name() const override { return "Notif"; }
  void enter() override;
  bool input(Gesture g) override;
  void event(const Event& e) override;
  void update(uint32_t now) override;
  void render(Adafruit_GFX& g, uint32_t now) override;
  bool keepAwake() const override { return _incoming; }

private:
  struct Line { uint8_t start, len; };
  void layout();
  uint8_t _idx = 0;                 // 0 = terbaru
  bool _incoming = false;
  uint32_t _shownAt = 0, _showMs = 0;
  Line _lines[14];
  uint8_t _n = 0;
};

// Panggilan masuk (CALL): nama penelepon + dering. Tap = bisukan dering Lokana.
class CallModule : public Module {
public:
  const char* name() const override { return "Panggilan"; }
  bool hidden() const override { return true; }
  void exit() override;
  bool input(Gesture g) override;
  void event(const Event& e) override;
  void update(uint32_t now) override;
  void render(Adafruit_GFX& g, uint32_t now) override;
  bool keepAwake() const override { return _active; }

private:
  void stop();
  bool _active = false, _muted = false;
  uint32_t _since = 0;
};
