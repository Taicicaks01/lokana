#include "image_module.h"
#include "config.h"
#include "core/core.h"
#include "drivers/buzzer.h"
#include "drivers/display.h"

// Slot terisi berikutnya setelah _slot (berputar). false jika galeri kosong.
bool ImageModule::nextSlot() {
  for (uint8_t k = 1; k <= imgstore::SLOTS; k++) {
    uint8_t s = (_slot + k - 1) % imgstore::SLOTS + 1;
    if (imgstore::load(s, _img)) {
      _slot = s;
      _shownAt = millis();
      _labelUntil = _shownAt + 1200;
      return true;
    }
  }
  _img.release();
  return false;
}

void ImageModule::enter() {
  if (_incoming) return;                            // dibuka oleh gambar masuk
  _slot = 0;
  nextSlot();
}

void ImageModule::exit() {
  if (!_incoming) _img.release();                   // hemat RAM saat modul lain tampil
}

bool ImageModule::input(Gesture g) {
  if (g != G_TAP) return false;
  if (_incoming) { _incoming = false; _img.release(); core::back(); return true; }
  if (!nextSlot()) core::toast("Galeri kosong", 800);
  buzzer::play(MEL_TAP);
  return true;
}

void ImageModule::event(const Event& e) {
  if (e.type != EV_BITMAP) return;
  _img.swap(imgstore::current());                   // pindahkan, tanpa salin
  imgstore::current().release();
  _incoming = !_img.empty();
  _slot = 0;
  _shownAt = millis();
  _labelUntil = 0;
  buzzer::play(MEL_SELECT);
  core::goTo(name());
}

void ImageModule::update(uint32_t now) {
  if (_incoming && _img.durationS && (int32_t)(now - _shownAt) > (int32_t)_img.durationS * 1000) {
    _incoming = false;
    _img.release();
    core::back();
  }
}

void ImageModule::render(Adafruit_GFX& g, uint32_t now) {
  g.setTextColor(1);
  if (_img.empty()) {
    g.setTextSize(1);
    display::centerText("Galeri kosong", SCREEN_H / 2 - (SCREEN_H >= 64 ? 10 : 8));
    display::centerText("kirim dari aplikasi", SCREEN_H / 2 + 2);
    return;
  }
  // Bingkai yang tampil: berputar terus (loops 0) atau berhenti di bingkai terakhir
  uint32_t step = (now - _shownAt) / (_img.frameMs ? _img.frameMs : 100);
  uint8_t f;
  if (_img.loops && step >= (uint32_t)_img.loops * _img.frames) f = _img.frames - 1;
  else f = step % _img.frames;
  // Format spesifikasi = format drawBitmap Adafruit: baris dibulatkan ke byte, MSB = kiri
  g.drawBitmap(_img.x, _img.y, _img.frame(f), _img.w, _img.h, 1);

  // Label slot sebentar setelah berganti, di pojok kanan bawah
  if (_slot && (int32_t)(_labelUntil - now) > 0) {
    char s[8];
    snprintf(s, sizeof(s), "Slot %u", _slot);
    int w = display::textWidth(s) + 4;
    g.fillRect(SCREEN_W - w, SCREEN_H - 9, w, 9, 1);
    g.setTextColor(0);
    g.setCursor(SCREEN_W - w + 2, SCREEN_H - 8);
    g.print(s);
    g.setTextColor(1);
  }
}
