#include "guide_module.h"
#include "config.h"
#include "core/core.h"
#include "drivers/buzzer.h"
#include "drivers/display.h"

// ---------- Tata letak ----------
#if SCREEN_H >= 64
static const int PAD_X = 22, PAD_Y = 26, PAD_R = 12, FINGER_R = 7;
static const int TXT_X = 48, LABEL_Y = 8, DESC_Y = 30, LABEL_SZ = 2, FOOT_Y = 56;
#else
static const int PAD_X = 16, PAD_Y = 13, PAD_R = 9, FINGER_R = 5;
static const int TXT_X = 36, LABEL_Y = 2, DESC_Y = 13, LABEL_SZ = 1, FOOT_Y = -1;
#endif

struct Card {
  const char* label;   // kosong = kartu khusus (sapaan / aplikasi)
  uint8_t taps;        // 0 = tahan
  const char* l1;
  const char* l2;
};

static const Card GUIDE_CARDS[GuideModule::CARDS] = {
  {"", 0, "", ""},                                   // Hai!
  {"TAP", 1, "aksi di modul", "yang tampil"},
  {"2x TAP", 2, "ganti ke", "modul lain"},
  {"3x TAP", 3, "buka menu", "pengaturan"},
  {"TAHAN", 0, "ubah di menu", "atau tidurkan"},
  {"", 0, "", ""},                                   // aplikasi
};

void GuideModule::enter() { _t0 = millis(); }

void GuideModule::finish() {
  _freeze = 0;
  core::back();
}

bool GuideModule::input(Gesture g) {
  (void)g;
  buzzer::play(MEL_SELECT);
  finish();
  return true;
}

void GuideModule::event(const Event& e) {
  if (e.type != EV_GUIDE) return;
  _freeze = e.value > 0 ? (uint32_t)e.value : 0;
  core::goTo(name());
  enter();
}

void GuideModule::update(uint32_t now) {
  if (!_freeze && elapsed(now) >= CARDS * CARD_MS) finish();
}

// Sensor sentuh + jari yang menekan: taps kali dalam satu putaran, atau ditahan (taps = 0).
static void drawPad(Adafruit_GFX& g, uint32_t t, uint8_t taps) {
  g.drawCircle(PAD_X, PAD_Y, PAD_R, 1);
  const uint32_t start = 350;
  if (t < start) return;
  uint32_t c = (t - start) % 1700;
  if (taps) {
    for (uint8_t k = 0; k < taps; k++) {
      uint32_t at = k * 230;
      if (c < at) break;
      uint32_t d = c - at;
      if (d < 110) g.fillCircle(PAD_X, PAD_Y, FINGER_R, 1);       // jari menekan
      if (d < 320) g.drawCircle(PAD_X, PAD_Y, PAD_R + 2 + d / 40, 1);   // riak
    }
    return;
  }
  // Tahan: jari menekan 1 detik, lingkaran dalam mengisi sampai penuh
  if (c < 1000) {
    g.fillCircle(PAD_X, PAD_Y, FINGER_R, 1);
    int r = FINGER_R + 1 + (int)((PAD_R - FINGER_R - 2) * c / 1000);
    g.drawCircle(PAD_X, PAD_Y, r, 1);
  } else if (c < 1300) {
    g.drawCircle(PAD_X, PAD_Y, PAD_R + 2 + (c - 1000) / 40, 1);
  }
}

static void drawPhone(Adafruit_GFX& g, int x, int y, int w, int h) {
  g.drawRoundRect(x, y, w, h, 4, 1);
  g.drawFastHLine(x + w / 2 - 3, y + 3, 6, 1);                 // speaker
  g.drawRect(x + 3, y + 7, w - 6, h - 14, 1);                  // layar
  g.fillRect(x + 5, y + 10, w - 10, 3, 1);                     // "notifikasi" di layar
  g.drawFastHLine(x + 5, y + 15, w - 12, 1);
  g.drawFastHLine(x + w / 2 - 2, y + h - 4, 4, 1);             // tombol
}

void GuideModule::render(Adafruit_GFX& g, uint32_t now) {
  uint32_t t = elapsed(now);
  uint8_t i = min<uint32_t>(t / CARD_MS, CARDS - 1);
  uint32_t ct = t - i * CARD_MS;
  const Card& c = GUIDE_CARDS[i];
  // Kartu masuk dari kanan
  int dx = ct < 200 ? (int)(24 - ct * 24 / 200) : 0;

  g.setTextColor(1);
  g.setTextSize(1);
  if (i == 0) {
#if SCREEN_H >= 64
    g.setTextSize(2);
    display::centerText("Hai!", 6, 2);
    g.setTextSize(1);
    display::centerText("Aku Lokana.", 28);
    display::centerText("Begini cara pakai aku", 40);
#else
    display::centerText("Hai! Aku Lokana", 4);
    display::centerText("begini cara pakai aku", 16);
#endif
  } else if (i == CARDS - 1) {
#if SCREEN_H >= 64
    drawPhone(g, 10 + dx, 8, 22, 40);
#else
    drawPhone(g, 6 + dx, 2, 16, 26);
#endif
    g.setCursor(TXT_X + dx, LABEL_Y + 2);  g.print("Lebih lengkap");
    g.setCursor(TXT_X + dx, LABEL_Y + 14); g.print("di aplikasi");
#if SCREEN_H >= 64
    g.setCursor(TXT_X + dx, LABEL_Y + 26); g.print("Lokana di HP");
#endif
  } else {
    drawPad(g, ct, c.taps);
    g.setTextSize(LABEL_SZ);
    g.setCursor(TXT_X + dx, LABEL_Y); g.print(c.label);
    g.setTextSize(1);
    g.setCursor(TXT_X + dx, DESC_Y);  g.print(c.l1);
#if SCREEN_H >= 64
    g.setCursor(TXT_X + dx, DESC_Y + 10); g.print(c.l2);
#endif
  }

  // Kaki: titik posisi + petunjuk lewati
  if (FOOT_Y < 0) return;
  for (uint8_t k = 0; k < CARDS; k++) {
    int x = 3 + k * 6;
    if (k == i) g.fillCircle(x, FOOT_Y + 3, 2, 1);
    else g.drawPixel(x, FOOT_Y + 3, 1);
  }
  const char* hint = "sentuh: lewati";
  g.setCursor(SCREEN_W - display::textWidth(hint) - 1, FOOT_Y);
  g.print(hint);
}
