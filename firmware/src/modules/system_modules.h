#pragma once
#include "core/module.h"

// Layar sistem yang dibuka otomatis oleh event, tidak ikut giliran double-tap.

// Pairing BLE: menampilkan passkey 6 digit yang harus diketik di HP.
class PairModule : public Module {
public:
  const char* name() const override { return "Pairing"; }
  bool hidden() const override { return true; }
  bool input(Gesture g) override { (void)g; return true; }   // tombol tidak membatalkan
  void event(const Event& e) override;
  void update(uint32_t now) override;
  void render(Adafruit_GFX& g, uint32_t now) override;
  bool keepAwake() const override { return _state != P_IDLE; }

private:
  enum State : uint8_t { P_IDLE, P_WAIT, P_OK, P_FAIL };
  State _state = P_IDLE;
  uint32_t _code = 0, _doneAt = 0;
};

// Cari kunci (FIND_KEYS): bunyi keras + layar berkedip sampai disentuh / waktu habis.
class FindModule : public Module {
public:
  const char* name() const override { return "Cari"; }
  bool hidden() const override { return true; }
  void exit() override;
  bool input(Gesture g) override;
  void event(const Event& e) override;
  void update(uint32_t now) override;
  void render(Adafruit_GFX& g, uint32_t now) override;
  bool keepAwake() const override { return _active; }

private:
  void stop();
  bool _active = false;
  uint32_t _until = 0;
};

// Cari HP (FIND_PHONE): dibuka dari menu, meminta HP berbunyi.
// Tap / 30 detik = hentikan; HP mengirim FIND_PHONE op 0 = sudah ditemukan.
class PhoneModule : public Module {
public:
  const char* name() const override { return "Cari HP"; }   // modul biasa (double-tap) sejak 0.5.2
  void exit() override;
  bool input(Gesture g) override;
  void event(const Event& e) override;
  void update(uint32_t now) override;
  void render(Adafruit_GFX& g, uint32_t now) override;
  bool keepAwake() const override { return _active; }

private:
  void start();
  void stop(bool tellPhone, const char* msg);
  bool _active = false;
  uint32_t _since = 0;
};
