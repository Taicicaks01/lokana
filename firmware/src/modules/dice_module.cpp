#include "dice_module.h"
#include "config.h"
#include "core/core.h"
#include "drivers/buzzer.h"
#include "drivers/display.h"
#include <esp_random.h>

enum DiceType : uint8_t { D1x6, D2x6, D4, D8, D10, D12, D20, COIN, TYPE_COUNT };
static const char* const TYPE_NAME[TYPE_COUNT] = {"1d6", "2d6", "d4", "d8", "d10", "d12", "d20", "Koin"};
static const uint16_t ROLL_MS = 900;

// Angka acak 1..n tanpa bias modulo, dari hardware RNG
static uint8_t rnd(uint8_t n) {
  uint32_t limit = UINT32_MAX - (UINT32_MAX % n);
  uint32_t r;
  do { r = esp_random(); } while (r >= limit);
  return (uint8_t)(r % n) + 1;
}

uint8_t DiceModule::sides() const {
  static const uint8_t S[TYPE_COUNT] = {6, 6, 4, 8, 10, 12, 20, 2};
  return S[_type];
}

bool DiceModule::input(Gesture g) {
  if (g == G_TAP) { roll(); return true; }
  if (g == G_LONG && !_rolling) {
    _type = (_type + 1) % TYPE_COUNT;
    _a = _b = 0;
    buzzer::play(MEL_SELECT);
    core::toast(TYPE_NAME[_type], 700);
    return true;
  }
  return false;
}

void DiceModule::event(const Event& e) {
  if (e.type == EV_ROLL) { core::goTo(name()); roll(); }
}

void DiceModule::roll() {
  if (_rolling) return;
  _rolling = true;
  _rollAt = _nextFlip = millis();
  _step = 40;
}

void DiceModule::finish() {
  _rolling = false;
  _a = rnd(sides());
  _b = (_type == D2x6) ? rnd(6) : 0;
  uint8_t maxv = sides(), total = _a + _b;
  bool best = (_type == D2x6) ? total == 12 : (_type != COIN && _a == maxv);
  bool worst = (_type == D2x6) ? total == 2 : (_type != COIN && _a == 1);
  if (best) { buzzer::play(MEL_WIN); core::toast(_type == D20 ? "NAT 20!" : "MANTAP!", 900); }
  else if (worst) { buzzer::play(MEL_LOSE); core::toast("Yaah...", 800); }
  else buzzer::play(MEL_ROLL_DONE);
  Serial.printf("[dadu] %s -> %d%s\r\n", TYPE_NAME[_type], _a, _b ? (String(" + ") + _b).c_str() : "");
}

void DiceModule::update(uint32_t now) {
  if (!_rolling) return;
  if ((int32_t)(now - _rollAt) >= ROLL_MS) { finish(); return; }
  if ((int32_t)(now - _nextFlip) >= 0) {           // ganti muka acak, makin lama makin pelan
    _a = rnd(sides());
    _b = (_type == D2x6) ? rnd(6) : 0;
    _nextFlip = now + _step;
    _step += 18;
    buzzer::play(MEL_TICK);
  }
}

// ---------- Tata letak ----------
#if SCREEN_H >= 64
static const int DIE1 = 44, DIE2 = 40;          // sisi dadu: 1d6, 2d6
static const int DIE_Y = 12, SHAKE = 2;
static const int COIN_D = 44, COIN_X = 28, COIN_TX = 56;   // diameter, pusat x, x teks
static const int NUM_SIZE = 5;                  // angka besar d4..d20
#else
static const int DIE1 = 28, DIE2 = 28;
static const int DIE_Y = 2, SHAKE = 1;
static const int COIN_D = 28, COIN_X = 30, COIN_TX = 54;
static const int NUM_SIZE = 3;
#endif

// Dadu d6 berukuran s x s; posisi & jari-jari pips mengikuti ukuran
void DiceModule::drawD6(Adafruit_GFX& g, int x, int y, int s, uint8_t v) {
  g.fillRoundRect(x, y, s, s, s * 5 / 28, 1);
  const int L = s / 4, C = s / 2, R = s - s / 4, pr = max(2, s / 9);
  auto pip = [&](int px, int py) { g.fillCircle(x + px, y + py, pr, 0); };
  if (v % 2 == 1) pip(C, C);
  if (v >= 2) { pip(L, L); pip(R, R); }
  if (v >= 4) { pip(R, L); pip(L, R); }
  if (v == 6) { pip(L, C); pip(R, C); }
}

void DiceModule::render(Adafruit_GFX& g, uint32_t now) {
  int shake = _rolling ? ((int)((now / 30) % 3) - 1) * SHAKE : 0;
  g.setTextColor(1);
  g.setTextSize(1);
  g.setCursor(0, 0); g.print(TYPE_NAME[_type]);
  const int x1 = (SCREEN_W - DIE1) / 2;                       // 1d6 di tengah
#if SCREEN_H >= 64
  const int x2a = 2, x2b = 2 + DIE2 + 4, totX = 92, totY = DIE_Y + DIE2 / 2 - 7;
#else
  const int x2a = 22, x2b = 54, totX = 88, totY = 9;
#endif

  if (_a == 0 && !_rolling) {                       // belum dilempar
    if (_type == D2x6) {
      const int gap = 4, x = (SCREEN_W - 2 * DIE2 - gap) / 2;
      drawD6(g, x, DIE_Y, DIE2, 5); drawD6(g, x + DIE2 + gap, DIE_Y, DIE2, 2);
    }
    else if (_type == D1x6) drawD6(g, x1, DIE_Y, DIE1, 5);
    else display::centerText("?", DIE_Y + (DIE1 - 7 * (NUM_SIZE - 1)) / 2, NUM_SIZE - 1);
#if SCREEN_H >= 64
    g.setTextSize(1); g.setCursor(SCREEN_W - display::textWidth("tap: lempar"), 0); g.print("tap: lempar");
#else
    g.setTextSize(1); g.setCursor(0, 24); g.print("tap");
#endif
    return;
  }

  switch (_type) {
    case D1x6:
      drawD6(g, x1 + shake, DIE_Y, DIE1, _a);
      break;
    case D2x6: {
      drawD6(g, x2a + shake, DIE_Y, DIE2, _a);
      drawD6(g, x2b - shake, DIE_Y, DIE2, _b);
      if (!_rolling) {
        char s[6]; snprintf(s, sizeof(s), "=%d", _a + _b);
        g.setTextSize(2); g.setCursor(totX, totY); g.print(s);
      }
      break;
    }
    case COIN: {
      int w = _rolling ? 2 + abs((int)((now / 15) % COIN_D) - COIN_D / 2) * 2 : COIN_D;   // koin berputar
      g.fillRoundRect(COIN_X - w / 2, DIE_Y, w, COIN_D, min(w / 2, COIN_D / 2), 1);
      if (!_rolling) {
        const uint8_t ls = SCREEN_H >= 64 ? 3 : 2;  // huruf di koin
        g.setTextColor(0); g.setTextSize(ls);
        g.setCursor(COIN_X - 3 * ls + 1, DIE_Y + COIN_D / 2 - 7 * ls / 2); g.print(_a == 1 ? "A" : "G");
        g.setTextColor(1); g.setTextSize(2);
        g.setCursor(COIN_TX, DIE_Y + COIN_D / 2 - 7); g.print(_a == 1 ? "ANGKA" : "GAMBAR");
      }
      break;
    }
    default: {                                       // d4..d20: angka besar
      char s[4]; snprintf(s, sizeof(s), "%d", _a);
      g.setTextSize(NUM_SIZE);
      int w = display::textWidth(s, NUM_SIZE);
      g.setCursor((SCREEN_W - w) / 2 + shake, DIE_Y + (DIE1 - 7 * NUM_SIZE) / 2); g.print(s);
      break;
    }
  }
}
