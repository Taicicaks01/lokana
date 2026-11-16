#include "image_module.h"
#include "config.h"
#include "core/core.h"
#include "drivers/buzzer.h"
#include "drivers/display.h"

bool ImageModule::nextSlot() {
  for (uint8_t k = 1; k <= bmpstore::SLOTS + 1; k++) {
    int8_t s = (_slot + k) % (bmpstore::SLOTS + 1);
    if (s == 0) {
      if (bmpstore::current().empty()) continue;
      _img = bmpstore::current();
    } else if (!bmpstore::load(s, _img)) continue;
    _img.durationS = 0;
    _slot = s;
    _have = true;
    return true;
  }
  return false;
}

void ImageModule::enter() {
  if (_incoming) return;                            // dibuka oleh gambar masuk
  _slot = bmpstore::SLOTS;                          // nextSlot() mulai dari slot 0
  _have = nextSlot();
}

bool ImageModule::input(Gesture g) {
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

void ImageModule::event(const Event& e) {
  if (e.type != EV_BITMAP) return;
  _img = bmpstore::current();
  _incoming = _have = true;
  _slot = 0;
  _shownAt = millis();
  buzzer::play(MEL_SELECT);
  core::goTo(name());
}

void ImageModule::update(uint32_t now) {
  if (_incoming && _img.durationS && (int32_t)(now - _shownAt) > (int32_t)_img.durationS * 1000) {
    _incoming = false;
    core::back();
  }
}

void ImageModule::render(Adafruit_GFX& g, uint32_t now) {
  (void)now;
  g.setTextColor(1);
  if (!_have) {
    g.setTextSize(1);
    display::centerText("Belum ada gambar", SCREEN_H / 2 - (SCREEN_H >= 64 ? 10 : 8));
    display::centerText("kirim dari aplikasi", SCREEN_H / 2 + 2);
    return;
  }
  // Format spesifikasi = format drawBitmap Adafruit: baris dibulatkan ke byte, MSB = kiri
  g.drawBitmap(_img.x, _img.y, _img.data, _img.w, _img.h, 1);
}
