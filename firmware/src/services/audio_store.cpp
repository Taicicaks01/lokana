#include "audio_store.h"

static uint8_t data[audiostore::MAX];
static uint8_t n = 0;
static bool on = false;
static uint32_t at = 0;
static int hostStyle = -1;               // style terakhir dari host
static int pending = -1;                 // style yang belum diambil modul
static uint32_t demoUntil = 0, demoNext = 0;

namespace audiostore {

bool update(const uint8_t* b, uint8_t cnt, int style) {
  const bool started = !on;
  n = cnt > MAX ? MAX : cnt;
  memcpy(data, b, n);
  // Gaya dari host berlaku saat mulai dan saat nilainya berubah; tap di device bertahan sampai itu
  if (style >= 0 && (started || style != hostStyle)) pending = style;
  if (style >= 0) hostStyle = style;
  on = true;
  at = millis();
  return started;
}

uint8_t count() { return on ? n : 0; }
const uint8_t* bands() { return data; }
bool active() { return on; }

int takeStyle() {
  int s = pending;
  pending = -1;
  return s;
}

void demo(uint32_t ms, int style) {
  demoUntil = millis() + ms;
  if (!demoUntil) demoUntil = 1;
  demoNext = 0;
  hostStyle = -1;                         // gaya demo selalu diterapkan
  if (style >= 0) pending = style;
}

int tick(uint32_t now) {
  // Demo: 32 pita dari gelombang yang bergeser, bass berdenyut ±2x per detik
  if (demoUntil && (int32_t)(now - demoUntil) < 0 && (int32_t)(now - demoNext) >= 0) {
    demoNext = now + 40;
    uint8_t b[MAX];
    const float t = now / 1000.0f;
    const float beat = 0.5f + 0.5f * sinf(t * 12.6f);
    for (uint8_t i = 0; i < MAX; i++) {
      const float x = i / (float)(MAX - 1);
      float v = (1.0f - x) * (0.35f + 0.65f * beat) * 0.9f + 0.35f * (0.5f + 0.5f * sinf(t * 3.1f + x * 9.0f));
      v *= 0.75f + 0.25f * sinf(t * 7.3f + i * 1.7f);
      b[i] = (uint8_t)constrain((int)(v * 255), 0, 255);
    }
    if (update(b, MAX, -1)) return 1;
  }
  if (demoUntil && (int32_t)(now - demoUntil) >= 0) demoUntil = 0;
  if (!on || (int32_t)(now - at) < (int32_t)STALE_MS) return 0;
  on = false;
  n = 0;
  return -1;
}

}  // namespace audiostore
