#include "notif_module.h"
#include "config.h"
#include "core/core.h"
#include "core/settings.h"
#include "core/text_wrap.h"
#include "drivers/buzzer.h"
#include "drivers/display.h"
#include "services/notif_store.h"

// ---------- Tata letak ----------
static const int COLS = SCREEN_W / 6;            // 21 karakter per baris (font 6 px)
#if SCREEN_H >= 64
static const int TITLE_Y = 12, BODY_Y = 23, BODY_ROWS = 5;
#else
static const int TITLE_Y = 12, BODY_Y = 22, BODY_ROWS = 1;
#endif
static const int LINE_H = 8;
static const uint32_t SCROLL_DELAY = 2000, SCROLL_STEP = 1200;

void NotifModule::layout() {
  _n = notifstore::count() ? wrapText(notifstore::at(_idx).body, COLS, _lines, sizeof(_lines) / sizeof(_lines[0])) : 0;
}

void NotifModule::enter() {
  if (_incoming) return;                           // dibuka oleh notifikasi masuk
  _idx = 0;
  _shownAt = millis();
  layout();
}

bool NotifModule::input(Gesture g) {
  if (_incoming && (g == G_TAP || g == G_LONG)) { _incoming = false; core::back(); return true; }
  uint8_t n = notifstore::count();
  if (!n) return false;                            // kosong: tahan = layar mati seperti biasa
  if (g == G_TAP) {
    _idx = (_idx + 1) % n;
    buzzer::play(MEL_TAP);
  } else if (g == G_LONG) {
    notifstore::removeAt(_idx);
    if (_idx >= notifstore::count()) _idx = 0;
    core::toast("Dihapus", 600);
    buzzer::play(MEL_SELECT);
  } else return false;
  _shownAt = millis();
  layout();
  return true;
}

void NotifModule::event(const Event& e) {
  if (e.type != EV_NOTIF) return;
  if (e.value != 1) {                              // diperbarui / dihapus dari HP
    if (_idx >= notifstore::count()) _idx = 0;
    layout();
    return;
  }
  const Notif& n = notifstore::at(0);
  if (!n.silent()) buzzer::play(n.important() ? MEL_NOTIF_HI : MEL_NOTIF);
  Module* cur = core::current();
  if (cur && cur->hidden()) return;                // jangan menimpa pairing / cari / panggilan
  uint8_t popS = settings::get().notifPopupS;      // SETTINGS notif_popup: 0 = tidak muncul
  if (!popS) { if (cur == this) layout(); return; }
  _idx = 0;
  layout();
  _incoming = true;
  _shownAt = millis();
  uint32_t extra = _n > BODY_ROWS ? (_n - BODY_ROWS) * SCROLL_STEP : 0;
  _showMs = (popS + (n.important() ? 4 : 0)) * 1000UL + extra;
  core::goTo(name());
}

void NotifModule::update(uint32_t now) {
  if (_incoming && (int32_t)(now - _shownAt) > (int32_t)_showMs) { _incoming = false; core::back(); }
}

void NotifModule::render(Adafruit_GFX& g, uint32_t now) {
  uint8_t cnt = notifstore::count();
  g.setTextSize(1);
  g.setTextColor(1);
  if (!cnt) {
    display::centerText("Tidak ada notifikasi", SCREEN_H / 2 - (SCREEN_H >= 64 ? 10 : 8));
    display::centerText("dari HP", SCREEN_H / 2 + 2);
    return;
  }
  if (_idx >= cnt) _idx = 0;
  const Notif& n = notifstore::at(_idx);

  // Bilah judul: nama aplikasi kiri, posisi kanan (terbalik)
  char pos[8];
  snprintf(pos, sizeof(pos), "%u/%u", _idx + 1, cnt);
  g.fillRect(0, 0, SCREEN_W, 10, 1);
  g.setTextColor(0);
  char app[16];
  snprintf(app, sizeof(app), "%.*s", (int)(COLS - strlen(pos) - 1), n.app[0] ? n.app : "Notifikasi");
  g.setCursor(2, 1); g.print(app);
  g.setCursor(SCREEN_W - 2 - display::textWidth(pos), 1); g.print(pos);
  g.setTextColor(1);

  // Judul (dipotong satu baris)
  char t[24];
  snprintf(t, sizeof(t), "%.*s", COLS, n.title);
  g.setCursor(0, TITLE_Y); g.print(t);

  // Isi: bergulir per baris jika lebih panjang dari layar
  uint8_t first = 0;
  if (_n > BODY_ROWS) {
    uint32_t t0 = now - _shownAt;
    if (t0 > SCROLL_DELAY) first = ((t0 - SCROLL_DELAY) / SCROLL_STEP) % (_n - BODY_ROWS + 1);
  }
  for (uint8_t r = 0; r < BODY_ROWS && first + r < _n; r++) {
    const Line& l = _lines[first + r];
    g.setCursor(0, BODY_Y + r * LINE_H);
    for (uint8_t k = 0; k < l.len; k++) g.write(n.body[l.start + k]);
  }
}

// ================= Panggilan masuk =================
static const uint32_t CALL_MAX_MS = 60000;

// Gagang telepon klasik 22x22 (MSB = kiri, 3 byte per baris)
static const uint8_t PHONE_W = 22, PHONE_H = 22;
static const uint8_t PHONE_ICON[] PROGMEM = {
  0x1e, 0x00, 0x00, 0x7f, 0x80, 0x00, 0xff, 0xc0, 0x00, 0xff, 0xc0, 0x00,
  0xff, 0xc0, 0x00, 0xff, 0x80, 0x00, 0x7f, 0x00, 0x00, 0x7e, 0x00, 0x00,
  0x3e, 0x00, 0x00, 0x3e, 0x00, 0x00, 0x3f, 0x00, 0x00, 0x1f, 0x80, 0x00,
  0x1f, 0xc0, 0x70, 0x0f, 0xe0, 0xf8, 0x07, 0xf1, 0xf8, 0x03, 0xff, 0xfc,
  0x01, 0xff, 0xfc, 0x00, 0xff, 0xfc, 0x00, 0x7f, 0xfc, 0x00, 0x1f, 0xf8,
  0x00, 0x03, 0xf8, 0x00, 0x00, 0xf0,
};

void CallModule::stop() {
  if (!_active) return;
  _active = false;
  buzzer::stop();
  if (core::current() == this) core::back();
}

void CallModule::exit() {                          // pindah modul: dering Lokana berhenti
  if (_active) { _active = false; buzzer::stop(); }
}

bool CallModule::input(Gesture g) {
  (void)g;
  _muted = true;
  buzzer::stop();
  return true;
}

void CallModule::event(const Event& e) {
  if (e.type != EV_CALL) return;
  if (e.value == 0) {
    _active = true;
    _muted = false;
    _since = millis();
    core::goTo(name());
  } else stop();
}

void CallModule::update(uint32_t now) {
  if (!_active) return;
  if ((int32_t)(now - _since) > (int32_t)CALL_MAX_MS) { stop(); return; }
  if (!_muted && !buzzer::playing()) buzzer::play(MEL_CALL);   // ikut setelan suara
}

void CallModule::render(Adafruit_GFX& g, uint32_t now) {
  const char* who = notifstore::caller()[0] ? notifstore::caller() : "Tidak dikenal";
  g.setTextColor(1);
#if SCREEN_H >= 64
  // Ikon gagang telepon bergetar saat berdering
  int wob = _muted ? 0 : (int)((now / 80) % 3) - 1;
  int x = 5 + wob, y = 18;
  g.drawBitmap(x, y, PHONE_ICON, PHONE_W, PHONE_H, 1);
  display::centerText("Panggilan masuk", 2);
  g.drawFastHLine(0, 12, SCREEN_W, 1);
  uint8_t sz = strlen(who) <= 8 ? 2 : 1;
  int w = display::textWidth(who, sz);
  if (w > SCREEN_W - 34) {                         // nama panjang: berjalan
    int span = w + (SCREEN_W - 34);
    int off = (int)((now / 25) % (uint32_t)span);
    g.setTextSize(sz);
    g.setCursor(SCREEN_W - off, 22);
    g.print(who);
    g.fillRect(0, 16, 32, 26, 0);                   // tutup teks di belakang ikon
    g.drawBitmap(x, y, PHONE_ICON, PHONE_W, PHONE_H, 1);
  } else {
    g.setTextSize(sz);
    g.setCursor(34 + (SCREEN_W - 34 - w) / 2, sz == 2 ? 20 : 24);
    g.print(who);
  }
  g.setTextSize(1);
  display::centerText(_muted ? "dering dibisukan" : "tap: bisukan", 54);
#else
  display::centerText("Panggilan:", 2);
  display::centerText(who, 16);
#endif
}
