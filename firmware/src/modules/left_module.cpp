#include "left_module.h"
#include "config.h"
#include "core/core.h"
#include "drivers/buzzer.h"
#include "drivers/display.h"

static const uint32_t RING_MS = 30000;            // bunyi 30 detik
static const uint32_t SHOW_MS = 120000;           // layar tetap 2 menit, lalu kembali sendiri

void LeftModule::enter() {
  _since = millis();
  _ringing = true;
}

void LeftModule::exit() {                         // pindah modul (double-tap) = diam juga
  if (_ringing) { _ringing = false; buzzer::stop(); }
}

void LeftModule::close(const char* msg) {
  if (_ringing) { _ringing = false; buzzer::stop(); }
  if (msg) core::toast(msg, 1500);
  if (core::current() == this) core::back();
}

bool LeftModule::input(Gesture g) {
  (void)g;
  close(nullptr);
  return true;
}

void LeftModule::event(const Event& e) {
  if (e.type != EV_LEFT) return;
  if (e.value) core::goTo(name());                // enter() menyalakan bunyi
  else if (core::current() == this) close("HP kembali");
}

void LeftModule::update(uint32_t now) {
  uint32_t t = now - _since;
  if (_ringing && t >= RING_MS) { _ringing = false; buzzer::stop(); }
  if (_ringing && !buzzer::playing()) buzzer::play(MEL_FIND, true);   // bunyi walau suara dimatikan
  if (t >= SHOW_MS) close(nullptr);
}

// HP dengan tanda tanya di layarnya, bergetar selama berbunyi
static void drawPhone(Adafruit_GFX& g, int x, int y, int w, int h) {
  g.drawRoundRect(x, y, w, h, 4, 1);
  g.drawFastHLine(x + w / 2 - 3, y + 3, 6, 1);
  g.drawRect(x + 3, y + 7, w - 6, h - 14, 1);
  g.drawFastHLine(x + w / 2 - 2, y + h - 4, 4, 1);
  g.setTextSize(SCREEN_H >= 64 ? 2 : 1);
  g.setTextColor(1);
  int cw = SCREEN_H >= 64 ? 12 : 6, ch = SCREEN_H >= 64 ? 16 : 8;
  g.setCursor(x + (w - cw) / 2 + 1, y + (h - ch) / 2 + 1);
  g.print('?');
  g.setTextSize(1);
}

void LeftModule::render(Adafruit_GFX& g, uint32_t now) {
  int shake = _ringing && (now / 90) % 4 < 2 ? ((now / 90) % 2 ? 2 : -2) : 0;
  g.setTextColor(1);
#if SCREEN_H >= 64
  drawPhone(g, 10 + shake, 10, 26, 44);
  g.setTextSize(2);
  g.setCursor(46, 12); g.print("HP-mu");
  g.setTextSize(1);
  g.setCursor(46, 32); g.print("tertinggal?");
  const char* hint = _ringing ? "tap: diam" : "tap: tutup";
  g.setCursor(46, 50); g.print(hint);
#else
  drawPhone(g, 6 + shake, 2, 16, 28);
  g.setCursor(30, 4);  g.print("HP-mu tertinggal?");
  g.setCursor(30, 20); g.print(_ringing ? "tap: diam" : "tap: tutup");
#endif
}
