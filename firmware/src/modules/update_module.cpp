#include "update_module.h"
#include "config.h"
#include "core/core.h"
#include "drivers/buzzer.h"
#include "drivers/display.h"
#include "services/ota.h"

static const char* reasonText(int32_t r) {
  switch (r) {
    case 1: return "data rusak";
    case 2: return "gagal menulis";
    case 3: return "terputus";
    case 6: return "file salah";
    default: return "dibatalkan";
  }
}

void UpdateModule::event(const Event& e) {
  if (e.type != EV_OTA) return;
  if (e.value == 1) { _doneAt = 0; core::goTo(name()); return; }
  if (e.value == 2) return;                        // terpasang: render menampilkan "Memasang ulang"
  if (e.value == 3) { core::toast("Update berhasil", 2000); buzzer::play(MEL_WIN); return; }
  if (e.value == -100) {
    char t[32];
    snprintf(t, sizeof(t), "v%.10s gagal, versi lama", ota::rolledBackFrom());
    core::toast(t, 4000);
    buzzer::play(MEL_LOSE);
    return;
  }
  if (e.value < 0) {                               // gagal saat menerima
    char t[32];
    snprintf(t, sizeof(t), "Update gagal: %s", reasonText(-e.value));
    if (core::current() == this) core::back();
    core::toast(t, 2500);
    buzzer::play(MEL_LOSE);
  }
}

void UpdateModule::update(uint32_t now) {
  (void)now;
  if (!ota::active() && !ota::installing() && core::current() == this) core::back();
}

void UpdateModule::render(Adafruit_GFX& g, uint32_t now) {
  g.setTextColor(1);
  g.setTextSize(1);
  const uint32_t total = ota::total(), got = ota::received();
  const int pct = total ? (int)((uint64_t)got * 100 / total) : 0;
  char line[32];
#if SCREEN_H >= 64
  display::centerText(ota::installing() ? "Memasang ulang..." : "Memperbarui", 4);
  snprintf(line, sizeof(line), "Lokana OS v%.12s", ota::version());
  display::centerText(line, 18);
  const int x = 10, y = 32, w = SCREEN_W - 20, h = 10;
  g.drawRoundRect(x, y, w, h, 3, 1);
  int fill = ota::installing() ? w - 4 : (w - 4) * pct / 100;
  if (fill > 0) g.fillRect(x + 2, y + 2, fill, h - 4, 1);
  snprintf(line, sizeof(line), "%d%%  jangan dimatikan", ota::installing() ? 100 : pct);
  display::centerText(line, 50);
#else
  snprintf(line, sizeof(line), "Update %d%%", ota::installing() ? 100 : pct);
  display::centerText(line, 2);
  g.drawRect(8, 16, SCREEN_W - 16, 8, 1);
  int fill = (SCREEN_W - 20) * (ota::installing() ? 100 : pct) / 100;
  if (fill > 0) g.fillRect(10, 18, fill, 4, 1);
#endif
  (void)now;
}
