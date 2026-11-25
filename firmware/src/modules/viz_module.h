#pragma once
#include "core/module.h"

// Visualizer audio PC (AUDIO_BANDS, v0.8, Mode Meja): pita frekuensi dari Lokana Desktop, rendah di kiri.
// Membuka sendiri saat suara mulai, kembali ke modul sebelumnya 1,5 dtk setelah pesan berhenti.
// Hanya ikut giliran double-tap selama aktif; layar tetap menyala selama aktif (dapat daya USB).
// Tap = ganti gaya (Batang / Cermin). Tahan = layar mati seperti biasa.
class VizModule : public Module {
public:
  static const uint8_t STYLE_BARS = 0, STYLE_MIRROR = 1, STYLES = 2;
  const char* name() const override { return "Visualizer"; }
  bool available() const override;
  bool input(Gesture g) override;
  void event(const Event& e) override;
  void render(Adafruit_GFX& g, uint32_t now) override;
  bool keepAwake() const override;
  bool drawsBattery() const override { return true; }   // layar penuh: tanpa lencana

private:
  uint8_t _style = STYLE_BARS;
  uint16_t _peak[32] = {0};        // titik puncak per pita, satuan pita x 16 (turun halus)
  uint32_t _hold[32] = {0};        // titik puncak ditahan sampai waktu ini
  uint32_t _last = 0;
};
