#include "system_modules.h"
#include "config.h"
#include "core/core.h"
#include "drivers/buzzer.h"
#include "drivers/display.h"
#include "services/link.h"

// ================= Pairing =================
void PairModule::event(const Event& e) {
  if (e.type == EV_PAIR_CODE) {
    _code = (uint32_t)e.value;
    _state = P_WAIT;
    buzzer::play(MEL_PAIR);
    core::goTo(name());
  } else if (e.type == EV_PAIR_DONE && _state == P_WAIT) {
    _state = e.value ? P_OK : P_FAIL;
    _doneAt = millis();
    buzzer::play(e.value ? MEL_WIN : MEL_LOSE);
  }
}

void PairModule::update(uint32_t now) {
  if ((_state == P_OK || _state == P_FAIL) && (int32_t)(now - _doneAt) > 1800) {
    _state = P_IDLE;
    if (core::current() == this) core::back();
  }
}

void PairModule::render(Adafruit_GFX& g, uint32_t now) {
  (void)now;
  g.setTextColor(1);
  g.setTextSize(1);
  if (_state == P_OK || _state == P_FAIL) {
    display::centerText(_state == P_OK ? "Berhasil!" : "Gagal", SCREEN_H / 2 - 8, 2);
    if (SCREEN_H >= 64) display::centerText(_state == P_OK ? "HP tersambung" : "coba sambung lagi", 44);
    return;
  }
  char code[8];
  snprintf(code, sizeof(code), "%06lu", (unsigned long)_code);
#if SCREEN_H >= 64
  display::centerText("Pairing HP", 0);
  g.drawFastHLine(0, 10, SCREEN_W, 1);
  display::centerText("Ketik kode ini di HP:", 15);
  display::centerText(code, 28, 3);
  char nm[22];
  lklink::displayName(nm, sizeof(nm));
  display::centerText(nm, 56);
#else
  display::centerText("Kode pairing:", 0);
  display::centerText(code, 13, 2);
#endif
}

// ================= Cari kunci =================
void FindModule::stop() {
  if (!_active) return;
  _active = false;
  buzzer::stop();
  lklink::reportFindKeys(false, 0);               // aplikasi mengembalikan tombolnya
  if (core::current() == this) core::back();
}

void FindModule::exit() {                          // pindah modul (double-tap) = berhenti juga
  if (_active) { _active = false; buzzer::stop(); lklink::reportFindKeys(false, 0); }
}

bool FindModule::input(Gesture g) {
  (void)g;
  stop();
  return true;
}

void FindModule::event(const Event& e) {
  if (e.type != EV_FIND_KEYS) return;
  if (e.value > 0) {
    _active = true;
    _until = millis() + (uint32_t)e.value * 1000UL;
    lklink::reportFindKeys(true, (uint8_t)e.value);
    core::goTo(name());
  } else stop();
}

void FindModule::update(uint32_t now) {
  if (!_active) return;
  if ((int32_t)(now - _until) >= 0) { stop(); return; }
  if (!buzzer::playing()) buzzer::play(MEL_FIND, true);   // bunyi walau suara dimatikan
}

void FindModule::render(Adafruit_GFX& g, uint32_t now) {
  bool inv = (now / 250) % 2;                     // layar berkedip terang/gelap
  if (inv) g.fillRect(0, 0, SCREEN_W, SCREEN_H, 1);
  g.setTextColor(inv ? 0 : 1);
#if SCREEN_H >= 64
  display::centerText("Di sini!", 16, 2);
  display::centerText("sentuh untuk diam", 44);
#else
  display::centerText("Di sini!", 2, 2);
  display::centerText("sentuh: diam", 22);
#endif
  g.setTextColor(1);
}

// ================= Cari HP =================
static const uint32_t PHONE_MS = 30000;

void PhoneModule::stop(bool tellPhone, const char* msg) {
  if (!_active) return;
  _active = false;
  if (tellPhone) lklink::findPhone(false);
  if (core::current() == this) core::back();
  if (msg) core::toast(msg, 1200);
}

void PhoneModule::exit() {                        // pindah modul (double-tap) = hentikan juga
  if (_active) { _active = false; lklink::findPhone(false); }
}

bool PhoneModule::input(Gesture g) {
  (void)g;
  stop(true, "Dihentikan");
  return true;
}

void PhoneModule::event(const Event& e) {
  if (e.type != EV_FIND_PHONE) return;
  if (e.value == 0) { stop(false, "HP ditemukan"); return; }
  if (!lklink::findPhone(true)) {
    core::toast("HP tidak tersambung", 1500);
    buzzer::play(MEL_LOSE);
    return;
  }
  _active = true;
  _since = millis();
  buzzer::play(MEL_SELECT);
  core::goTo(name());
}

void PhoneModule::update(uint32_t now) {
  if (_active && (int32_t)(now - _since) > (int32_t)PHONE_MS) stop(true, nullptr);
}

void PhoneModule::render(Adafruit_GFX& g, uint32_t now) {
  g.setTextColor(1);
#if SCREEN_H >= 64
  const int px = 20, py = 12, pw = 22, ph = 38;   // ikon HP + gelombang sinyal
  g.drawRoundRect(px, py, pw, ph, 4, 1);
  g.fillRect(px + 3, py + 5, pw - 6, ph - 13, 1);
  g.fillCircle(px + pw / 2, py + ph - 4, 2, 1);
  uint8_t k = (now / 300) % 4;
  for (uint8_t i = 1; i <= 3; i++)
    if (i <= k) g.drawCircleHelper(px + pw, py + ph / 2, 3 + i * 5, 2 | 4, 1);
  g.setTextSize(1);
  g.setCursor(66, 18); g.print("Memanggil");
  g.setCursor(66, 30); g.print("HP...");
  uint32_t left = (PHONE_MS - min(PHONE_MS, now - _since)) / 1000;
  char s[8]; snprintf(s, sizeof(s), "%lus", (unsigned long)left);
  g.setCursor(66, 42); g.print(s);
  display::centerText("tap: berhenti", 56);
#else
  display::centerText("Memanggil HP...", 4, 1);
  display::centerText("tap: berhenti", 20);
#endif
}
