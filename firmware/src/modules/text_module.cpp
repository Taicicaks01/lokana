#include "text_module.h"
#include "config.h"
#include "core/core.h"
#include "drivers/buzzer.h"
#include "drivers/display.h"
#include "core/text_wrap.h"
#include <Fonts/FreeSans9pt7b.h>
#include <Fonts/FreeSans12pt7b.h>
#include <Fonts/FreeSans18pt7b.h>
#include <Fonts/FreeSansBold9pt7b.h>
#include <Fonts/FreeSansBold12pt7b.h>
#include <Fonts/FreeSansBold18pt7b.h>
#include <Fonts/FreeSerif9pt7b.h>
#include <Fonts/FreeSerif12pt7b.h>
#include <Fonts/FreeSerif18pt7b.h>
#include <Fonts/FreeMonoBold9pt7b.h>
#include <Fonts/FreeMonoBold12pt7b.h>
#include <Fonts/FreeMonoBold18pt7b.h>

void TextModule::show(const TextMsg& m) {
  _msg = m;
  _empty = !_msg.text[0];
  _shownAt = millis();
  layout();
}

// ---------- Font ----------
// Ukuran 1-3: font piksel diskalakan 1x-3x; font GFX memakai 9 / 12 / 18 pt.
static const GFXfont* const GFX_FONTS[textstore::FONTS][3] = {
  {nullptr, nullptr, nullptr},
  {&FreeSans9pt7b, &FreeSans12pt7b, &FreeSans18pt7b},
  {&FreeSansBold9pt7b, &FreeSansBold12pt7b, &FreeSansBold18pt7b},
  {&FreeSerif9pt7b, &FreeSerif12pt7b, &FreeSerif18pt7b},
  {&FreeMonoBold9pt7b, &FreeMonoBold12pt7b, &FreeMonoBold18pt7b},
};

static const GFXglyph& glyph(const GFXfont* f, char c) {
  uint8_t ch = (uint8_t)c;
  if (ch < f->first || ch > f->last) ch = '?';
  return f->glyph[ch - f->first];
}

TextModule::Metrics TextModule::metrics(uint8_t font, uint8_t size) {
  const GFXfont* f = font < textstore::FONTS ? GFX_FONTS[font][size - 1] : nullptr;
  if (!f) return {nullptr, size, 8 * size, 7 * size};
  int asc = -glyph(f, 'A').yOffset;                // tinggi huruf kapital
  const GFXglyph& g = glyph(f, 'g');
  int desc = g.height + g.yOffset;                 // ekor huruf (g, y, p)
  return {f, 1, asc + desc + 2, asc};
}

int TextModule::charW(const Metrics& m, char c) { return m.f ? glyph(m.f, c).xAdvance : 6 * m.scale; }

int TextModule::textW(const char* s, int n) const {
  int w = 0;
  for (int i = 0; i < n && s[i]; i++) w += charW(_m, s[i]);
  return w;
}

// Pilih ukuran: terbesar yang muat (otomatis), atau ukuran dari aplikasi.
// Kalau ukuran 1 pun tidak muat, teks bergulir ke atas.
void TextModule::layout() {
  const uint8_t maxSz = _msg.font ? 3 : (SCREEN_H >= 64 ? 3 : 2);
  if (_msg.style == 1) {                            // berjalan: satu baris
    for (char* c = _msg.text; *c; c++) if (*c == '\n') *c = ' ';
    _m = metrics(_msg.font, _msg.size ? _msg.size : maxSz);
    return;
  }
  uint8_t sz = _msg.size ? _msg.size : maxSz;
  for (;; sz--) {
    _m = metrics(_msg.font, sz);
    const Metrics m = _m;
    _n = wrapTextPx(_msg.text, SCREEN_W - 2, [&m](char c) { return charW(m, c); }, _lines, MAX_LINES);
    if (_msg.size || sz == 1 || _n * _m.lineH <= SCREEN_H + 2) break;
  }
  _vscroll = _n * _m.lineH > SCREEN_H + 2;
}

bool TextModule::nextSlot() {
  for (uint8_t k = 1; k <= textstore::SLOTS + 1; k++) {
    int8_t s = (_slot + k) % (textstore::SLOTS + 1);
    TextMsg m;
    if (s == 0) { if (!textstore::current().text[0]) continue; m = textstore::current(); }
    else if (!textstore::load(s, m)) continue;
    m.durationS = 0;
    _slot = s;
    show(m);
    return true;
  }
  return false;
}

void TextModule::enter() {
  if (_incoming) return;                            // dibuka oleh pesan masuk
  _slot = textstore::SLOTS;                         // nextSlot() mulai dari slot 0
  if (!nextSlot()) show(TextMsg());
}

bool TextModule::input(Gesture g) {
  if (g != G_TAP) return false;
  if (_incoming) { _incoming = false; core::back(); return true; }
  if (nextSlot()) {
    char t[12];
    if (_slot) snprintf(t, sizeof(t), "Slot %d", _slot); else strcpy(t, "Terakhir");
    core::toast(t, 600);
  }
  buzzer::play(MEL_TAP);
  return true;
}

void TextModule::event(const Event& e) {
  if (e.type != EV_TEXT) return;
  _incoming = true;
  uint8_t slot = e.value & 0xFF;                    // TEXT_SLOT SHOW: slot | duration_s << 8
  TextMsg m;
  if (slot && textstore::load(slot, m)) {
    m.durationS = (uint16_t)(e.value >> 8);
    _slot = slot;
    show(m);
  } else {
    _slot = 0;
    show(textstore::current());
  }
  buzzer::play(MEL_SELECT);
  core::goTo(name());
}

void TextModule::update(uint32_t now) {
  if (_incoming && _msg.durationS && (int32_t)(now - _shownAt) > (int32_t)_msg.durationS * 1000) {
    _incoming = false;
    core::back();
  }
}

void TextModule::render(Adafruit_GFX& g, uint32_t now) {
  g.setTextColor(1);
  if (_empty) {
    g.setTextSize(1);
    display::centerText("Belum ada teks", SCREEN_H / 2 - (SCREEN_H >= 64 ? 10 : 8));
    display::centerText("kirim dari aplikasi", SCREEN_H / 2 + 2);
    return;
  }
  draw(g, now - _shownAt);
  g.setFont(nullptr);                               // modul lain & toast memakai font piksel
  g.setTextSize(1);
}

void TextModule::draw(Adafruit_GFX& g, uint32_t t) {
  g.setFont(_m.f);
  g.setTextSize(_m.scale);
  // Font GFX: kursor = garis dasar (baseline). Font piksel: kursor = sisi atas.
  const int base = _m.f ? _m.asc : 0;

  if (_msg.style == 1) {                            // berjalan dari kanan ke kiri
    int w = textW(_msg.text, strlen(_msg.text));
    int x = SCREEN_W - (int)((t / 12) % (uint32_t)(w + SCREEN_W));
    g.setCursor(x, (SCREEN_H - _m.asc) / 2 + base);
    g.print(_msg.text);
    return;
  }
  if (_msg.style == 2 && (t % 1000) >= 650) return; // berkedip: padam sebentar

  int total = _n * _m.lineH, y0 = (SCREEN_H - total) / 2 + 1;
  if (_vscroll) {                                   // mulai dari atas, diam, gulir ke baris terakhir, diam, ulang
    const uint32_t hold = 1500, pxMs = 45;
    uint32_t over = total - SCREEN_H + 2, cycle = hold * 2 + over * pxMs, tt = t % cycle;
    y0 = -(int)(tt < hold ? 0 : min(over, (tt - hold) / pxMs));
  }
  for (uint8_t i = 0; i < _n; i++) {
    int y = y0 + i * _m.lineH;
    if (y <= -_m.lineH || y >= SCREEN_H) continue;
    const char* s = _msg.text + _lines[i].start;
    g.setCursor((SCREEN_W - textW(s, _lines[i].len)) / 2, y + base);
    for (uint8_t k = 0; k < _lines[i].len; k++) g.write(s[k]);
  }
}
