#include "monitor_module.h"
#include "config.h"
#include "core/core.h"
#include "drivers/buzzer.h"
#include "drivers/display.h"
#include "services/stats_store.h"

// Satu baris = 16 px: label kiri, nilai kanan, bar tipis di bawah (persen / suhu).
static const int ROW_H = 16;
static const int ROWS = SCREEN_H / ROW_H > 0 ? SCREEN_H / ROW_H : 1;   // 4 (128x64) atau 2 (128x32)
static const uint32_t PAGE_MS = 5000;
static const uint32_t SHIFT_MS = 120000;                              // geser piksel tiap 2 menit

static uint8_t pages() {
  uint8_t n = statsstore::count();
  return n ? (n + ROWS - 1) / ROWS : 1;
}

// Nilai: persen & suhu bulat; angka lain 1 desimal kalau < 100
static void formatValue(const Metric& m, char* out, size_t cap) {
  const int32_t v = m.v10;
  if (m.kind == 1 || m.kind == 2 || v >= 1000 || v <= -1000)
    snprintf(out, cap, "%ld%s", (long)((v >= 0 ? v + 5 : v - 5) / 10), m.unit);
  else
    snprintf(out, cap, "%s%ld.%ld%s", v < 0 ? "-" : "", (long)(labs(v) / 10), (long)(labs(v) % 10), m.unit);
}

bool MonitorModule::available() const { return statsstore::active(); }
bool MonitorModule::keepAwake() const { return statsstore::active(); }

void MonitorModule::enter() { _page = 0; _pageAt = millis(); }

bool MonitorModule::input(Gesture g) {
  if (g != G_TAP) return false;                    // tahan -> layar mati (Core)
  _page = (_page + 1) % pages();
  _pageAt = millis();
  buzzer::play(MEL_TAP);
  return true;
}

void MonitorModule::event(const Event& e) {
  if (e.type != EV_STATS) return;
  Module* cur = core::current();
  if (e.value == 0) {                              // PC berhenti mengirim
    if (cur == this) core::back();
    return;
  }
  if (cur && cur->hidden() && !cur->remoteOpen()) return;   // pairing / cari / panggilan / update
  if (cur != this) core::goTo(name(), true);
}

void MonitorModule::render(Adafruit_GFX& g, uint32_t now) {
  g.setTextColor(1);
  g.setTextSize(1);
  const uint8_t n = statsstore::count();
  if (!n) {
    display::centerText("Menunggu data PC", SCREEN_H / 2 - 4);
    return;
  }
  if (_page >= pages()) _page = 0;
  if ((int32_t)(now - _pageAt) >= (int32_t)PAGE_MS) {
    _page = (_page + 1) % pages();
    _pageAt = now;
  }
  // Geser piksel anti burn-in: (0,0) (1,0) (1,1) (0,1)
  static const int8_t SX[4] = {0, 1, 1, 0}, SY[4] = {0, 0, 1, 1};
  const uint8_t s = (now / SHIFT_MS) % 4;
  const int ox = SX[s], oy = SY[s];
  const int barW = SCREEN_W - 3;

  for (uint8_t r = 0; r < ROWS; r++) {
    const uint8_t i = _page * ROWS + r;
    if (i >= n) break;
    const Metric& m = statsstore::get(i);
    const int y = r * ROW_H + oy;
    g.setCursor(ox, y + 1);
    g.print(m.label);
    char v[16];
    formatValue(m, v, sizeof(v));
    g.setCursor(ox + SCREEN_W - 2 - display::textWidth(v), y + 1);
    g.print(v);
    if (m.kind == 1 || m.kind == 2) {             // bar 0..100 (persen, atau suhu dalam C)
      int32_t pct = m.v10 / 10;
      if (pct < 0) pct = 0;
      if (pct > 100) pct = 100;
      // Baris terakhir disisakan ruang untuk penanda halaman di kanan bawah
      const int bw = (r == ROWS - 1 && pages() > 1) ? barW - 4 * pages() - 2 : barW;
      g.drawFastHLine(ox, y + 12, bw, 1);           // garis dasar
      g.fillRect(ox, y + 10, (int)(pct * bw / 100), 3, 1);
    }
  }
  // Penanda halaman (titik kecil di kanan bawah) kalau lebih dari satu halaman
  const uint8_t p = pages();
  if (p > 1)
    for (uint8_t k = 0; k < p; k++) {
      const int x = ox + SCREEN_W - 2 - (p - 1 - k) * 4, yy = SCREEN_H - 2 + oy - 1;
      if (k == _page) g.fillRect(x - 1, yy - 1, 2, 2, 1);
      else g.drawPixel(x, yy, 1);
    }
}
