#include "text_module.h"
#include "config.h"
#include "core/core.h"
#include "drivers/buzzer.h"
#include "drivers/display.h"

// Bungkus kata: baris maks `cols` karakter, '\n' = baris baru, kata terlalu panjang dipotong
template <typename L>
static uint8_t wrap(const char* t, int cols, L* out, uint8_t maxLines) {
  int len = strlen(t), s = 0;
  uint8_t n = 0;
  while (s <= len && n < maxLines) {
    int e = s, sp = -1;
    while (e < len && t[e] != '\n' && e - s < cols) { if (t[e] == ' ') sp = e; e++; }
    if (e >= len || t[e] == '\n') {                 // sisa muat di satu baris
      out[n++] = {(uint8_t)s, (uint8_t)(e - s)};
      if (e >= len) break;
      s = e + 1;
    } else if (t[e] == ' ') { out[n++] = {(uint8_t)s, (uint8_t)(e - s)}; s = e + 1; }
    else if (sp > s)        { out[n++] = {(uint8_t)s, (uint8_t)(sp - s)}; s = sp + 1; }
    else                    { out[n++] = {(uint8_t)s, (uint8_t)cols}; s += cols; }
  }
  return n;
}

void TextModule::show(const TextMsg& m) {
  _msg = m;
  _empty = !_msg.text[0];
  _shownAt = millis();
  layout();
}

// Pilih ukuran font: terbesar yang muat (otomatis), atau ukuran dari aplikasi.
// Kalau ukuran 1 pun tidak muat, teks bergulir ke atas.
void TextModule::layout() {
  if (_msg.style == 1) {                            // berjalan: satu baris
    for (char* c = _msg.text; *c; c++) if (*c == '\n') *c = ' ';
    _sz = _msg.size ? _msg.size : (SCREEN_H >= 64 ? 3 : 2);
    return;
  }
  const uint8_t maxSz = SCREEN_H >= 64 ? 3 : 2;
  uint8_t sz = _msg.size ? _msg.size : maxSz;
  for (;; sz--) {
    _n = wrap(_msg.text, SCREEN_W / (6 * sz), _lines, MAX_LINES);
    if (_msg.size || sz == 1 || _n * 8 * sz <= SCREEN_H) break;
  }
  _sz = sz;
  _vscroll = _n * 8 * _sz > SCREEN_H;
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
  _slot = 0;
  show(textstore::current());
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
  uint32_t t = now - _shownAt;
  g.setTextSize(_sz);
  const int cw = 6 * _sz, lh = 8 * _sz;

  if (_msg.style == 1) {                            // berjalan dari kanan ke kiri
    int w = strlen(_msg.text) * cw;
    int x = SCREEN_W - (int)((t / 12) % (uint32_t)(w + SCREEN_W));
    g.setCursor(x, (SCREEN_H - 7 * _sz) / 2);
    g.print(_msg.text);
    return;
  }
  if (_msg.style == 2 && (t % 1000) >= 650) return; // berkedip: padam sebentar

  int total = _n * lh;
  int y0 = _vscroll ? SCREEN_H - (int)((t / 50) % (uint32_t)(total + SCREEN_H))
                    : (SCREEN_H - total) / 2 + 1;
  for (uint8_t i = 0; i < _n; i++) {
    int y = y0 + i * lh;
    if (y <= -lh || y >= SCREEN_H) continue;
    g.setCursor((SCREEN_W - _lines[i].len * cw) / 2, y);
    for (uint8_t k = 0; k < _lines[i].len; k++) g.write(_msg.text[_lines[i].start + k]);
  }
}
