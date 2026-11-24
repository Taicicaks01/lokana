#include "nav_module.h"
#include "config.h"
#include "core/core.h"
#include "drivers/buzzer.h"
#include "drivers/display.h"
#include "services/nav_store.h"

// ---------- Tata letak ----------
// 128x64: [panah 32x32][jarak besar + bilah mendekat] / instruksi / jalan / waktu tiba
// 128x32: [panah 32x32][jarak] / instruksi (jalan di baris kedua kalau muat)
static const int ICON = 32, TEXT_X = 38;
#if SCREEN_H >= 64
static const int DIST_Y = 6, BAR_Y = 26, INSTR_Y = 36, STREET_Y = 46, ETA_Y = 56;
#else
static const int DIST_Y = 0, BAR_Y = -1, INSTR_Y = 17, STREET_Y = 25, ETA_Y = -1;
#endif

// Panah lurus sederhana kalau HP tidak mengirim ikon
static void defaultArrow(Adafruit_GFX& g, int x, int y) {
  g.fillTriangle(x + 16, y + 2, x + 4, y + 16, x + 28, y + 16, 1);
  g.fillRect(x + 12, y + 16, 8, 14, 1);
}

// Satu baris teks ukuran 1. Kalau lebih lebar dari layar: diam 1,5 dtk, lalu berjalan ke kiri dan berulang.
static void line(Adafruit_GFX& g, const char* s, int y, uint32_t now, uint32_t since) {
  if (!s[0] || y < 0) return;
  const int w = display::textWidth(s);
  int x = 0;
  if (w > SCREEN_W) {
    const uint32_t span = (uint32_t)(w - SCREEN_W + 24) * 33;   // ±30 px/dtk
    const uint32_t t = (now - since) % (1500 + span + 1500);
    x = t < 1500 ? 0 : -(int)(min(t - 1500, span) / 33);
  }
  g.setTextSize(1);
  g.setTextWrap(false);
  g.setCursor(x, y);
  g.print(s);
  g.setTextWrap(true);
}

bool NavModule::available() const { return navstore::get().active; }

bool NavModule::keepAwake() const { return navstore::near(); }

void NavModule::event(const Event& e) {
  if (e.type != EV_NAV) return;
  Module* cur = core::current();
  if (e.value == navstore::NV_NONE) {               // selesai / berhenti / HP terputus
    if (cur == this) {
      core::toast(e.text[0] ? e.text : "Navigasi selesai", 1500);
      core::back();
    }
    return;
  }
  // Jangan menimpa pairing / cari / panggilan / update. Panduan & Tertinggal (remoteOpen) boleh ditimpa.
  if (cur && cur->hidden() && !cur->remoteOpen()) return;
  if (cur != this) core::goTo(name(), e.value == navstore::NV_START);
  if (e.value == navstore::NV_NEAR || e.value == navstore::NV_TURN) buzzer::play(MEL_NOTIF);
}

void NavModule::render(Adafruit_GFX& g, uint32_t now) {
  const NavInfo& n = navstore::get();
  g.setTextColor(1);
  if (!n.active) {
    display::centerText("Tidak ada navigasi", SCREEN_H / 2 - 4);
    return;
  }

  // Panah
  if (n.iconW) g.drawBitmap((ICON - n.iconW) / 2, (ICON - n.iconH) / 2, n.icon, n.iconW, n.iconH, 1);
  else defaultArrow(g, 0, 0);

  // Jarak: teks dari HP, atau dihitung dari meter
  char d[16];
  if (n.distText[0]) strlcpy(d, n.distText, sizeof(d));
  else if (n.distM == 0xFFFFFFFF) d[0] = 0;
  else if (n.distM < 1000) snprintf(d, sizeof(d), "%lu m", (unsigned long)n.distM);
  else snprintf(d, sizeof(d), "%.1f km", n.distM / 1000.0f);
  const uint8_t size = display::textWidth(d, 2) <= SCREEN_W - TEXT_X ? 2 : 1;
  g.setTextSize(size);
  g.setCursor(TEXT_X, DIST_Y + (size == 2 ? 0 : 4));
  g.print(d);
  g.setTextSize(1);

  // Bilah mendekat: penuh saat sampai di belokan (hanya < 300 m)
  if (BAR_Y >= 0 && n.distM <= navstore::NEAR_M) {
    const int bw = SCREEN_W - TEXT_X - 2;
    g.drawRect(TEXT_X, BAR_Y, bw, 4, 1);
    g.fillRect(TEXT_X + 1, BAR_Y + 1, (int)((navstore::NEAR_M - n.distM) * (bw - 2) / navstore::NEAR_M), 2, 1);
  }

  line(g, n.instr, INSTR_Y, now, n.changedAt);
  line(g, n.street, STREET_Y, now, n.changedAt);

  // Waktu tiba
  if (ETA_Y >= 0) {
    char e[24] = {0};
    if (n.etaText[0]) strlcpy(e, n.etaText, sizeof(e));
    else if (n.etaMin != 0xFFFF) snprintf(e, sizeof(e), "%u mnt lagi", n.etaMin);
    if (e[0]) { g.setCursor(0, ETA_Y); g.print(e); }
  }
}
