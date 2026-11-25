#include "viz_module.h"
#include "config.h"
#include "core/core.h"
#include "drivers/buzzer.h"
#include "services/audio_store.h"

static const uint32_t HOLD_MS = 300;       // titik puncak diam sebentar sebelum turun
static const uint32_t FALL_PER_S = 255 * 16 * 10 / 12;   // turun penuh dalam ±1,2 dtk (satuan pita x 16)

bool VizModule::available() const { return audiostore::active(); }
bool VizModule::keepAwake() const { return audiostore::active(); }

bool VizModule::input(Gesture g) {
  if (g != G_TAP) return false;                    // tahan -> layar mati (Core)
  _style = (_style + 1) % STYLES;
  core::toast(_style == STYLE_BARS ? "Batang" : "Cermin", 700);
  buzzer::play(MEL_TAP);
  return true;
}

void VizModule::event(const Event& e) {
  if (e.type != EV_AUDIO) return;
  Module* cur = core::current();
  if (e.value == 0) {                              // suara berhenti / PC tidak mengirim lagi
    if (cur == this) core::back();
    return;
  }
  memset(_peak, 0, sizeof(_peak));
  if (cur && cur->hidden() && !cur->remoteOpen()) return;   // pairing / cari / panggilan / update
  if (cur != this) core::goTo(name(), true);
}

void VizModule::render(Adafruit_GFX& g, uint32_t now) {
  const int st = audiostore::takeStyle();
  if (st >= 0 && st < STYLES) _style = st;
  int32_t dt = (int32_t)(now - _last);
  if (dt < 0 || dt > 200) dt = 0;
  _last = now;
  const uint8_t n = audiostore::count();
  const int mid = SCREEN_H / 2;
  if (!n) {
    if (_style == STYLE_MIRROR) g.drawFastHLine(0, mid, SCREEN_W, 1);
    return;
  }
  const uint8_t* b = audiostore::bands();
  const int slot = SCREEN_W / n;
  const int bw = slot > 1 ? slot - 1 : 1;
  const int x0 = (SCREEN_W - slot * n) / 2;
  const uint32_t fall = FALL_PER_S * (uint32_t)dt / 1000;
  if (_style == STYLE_MIRROR) g.drawFastHLine(0, mid, SCREEN_W, 1);   // garis tengah utuh, juga di celah batang
  for (uint8_t i = 0; i < n && i < 32; i++) {
    // Titik puncak: naik seketika, ditahan HOLD_MS, lalu turun halus
    const uint16_t v16 = (uint16_t)b[i] * 16;
    if (v16 >= _peak[i]) { _peak[i] = v16; _hold[i] = now + HOLD_MS; }
    else if ((int32_t)(now - _hold[i]) >= 0) _peak[i] = _peak[i] > fall + v16 ? _peak[i] - fall : v16;
    const int x = x0 + i * slot;
    if (_style == STYLE_MIRROR) {
      // Dari garis tengah ke atas & bawah; garis tengah selalu tampak walau hening
      const int h = b[i] * mid / 255;
      g.fillRect(x, mid - h, bw, 2 * h + 1, 1);
      const int p = _peak[i] * mid / (255 * 16);
      if (p > h + 1) {
        g.drawFastHLine(x, mid - p, bw, 1);
        g.drawFastHLine(x, mid + p, bw, 1);
      }
    } else {
      // Dari bawah; titik puncak 1 px di atas batang
      const int h = b[i] * SCREEN_H / 255;
      if (h) g.fillRect(x, SCREEN_H - h, bw, h, 1);
      const int p = _peak[i] * (SCREEN_H - 1) / (255 * 16);
      if (p > h) g.drawFastHLine(x, SCREEN_H - 1 - p, bw, 1);
    }
  }
}
