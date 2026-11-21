#pragma once
#include <Adafruit_GFX.h>
#include "drivers/button.h"
#include "core/events.h"

// ============================================================
//  Module — "aplikasi" di Lokana. Setiap fitur adalah satu modul.
//  Area gambar: SCREEN_W x SCREEN_H (128 x 64; varian 0.91": 128 x 32).
//  Gambar memakai SCREEN_W / SCREEN_H, jangan angka tetap.
//
//  Gestur yang sampai ke modul: G_TAP dan G_LONG.
//  (Double-tap = pindah modul, triple-tap = menu, ditangani Core.)
//  Kembalikan true dari input() jika gestur dipakai modul.
//  G_LONG yang tidak dipakai -> layar dimatikan.
// ============================================================
class Module {
public:
  virtual ~Module() {}
  virtual const char* name() const = 0;
  virtual void enter() {}
  virtual void exit() {}
  virtual bool input(Gesture g) { (void)g; return false; }
  virtual void event(const Event& e) { (void)e; }
  virtual void update(uint32_t now) { (void)now; }
  virtual void render(Adafruit_GFX& g, uint32_t now) = 0;
  virtual bool keepAwake() const { return false; }
  // Modul sistem (pairing, cari kunci) tidak ikut giliran double-tap dan tidak bisa
  // dibuka lewat GOTO. Dibuka modulnya sendiri lewat core::goTo() saat ada event.
  virtual bool hidden() const { return false; }
  // Boleh dibuka lewat GOTO dari HP/PC. Bawaan: hanya modul biasa (Panduan: modul tersembunyi yang boleh).
  virtual bool remoteOpen() const { return !hidden(); }
  // Modul menggambar ikon baterai sendiri (Jam): Core tidak menimpa pojok kanan atas saat lemah/mengisi.
  virtual bool drawsBattery() const { return false; }
};
