#include "clock_module.h"
#include "config.h"
#include "core/clock.h"
#include "drivers/buzzer.h"
#include "drivers/display.h"
#include "drivers/hw.h"

static const uint16_t ANIM_MS = 350;

#if SCREEN_H >= 64
static const char* const DAYS_LONG[7] = {"Minggu", "Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu"};
static const char* const MONTHS[12] = {"Jan", "Feb", "Mar", "Apr", "Mei", "Jun",
                                       "Jul", "Agu", "Sep", "Okt", "Nov", "Des"};
// Digit ukuran 4: sel 24 x 32 px, 5 karakter = 120 px
static const int DIG_SIZE = 4, DIG_X = 4, DIG_Y = 4, DIG_CELL = 6 * DIG_SIZE;
static const int BAND_H = 36;          // pita digit; animasi dipotong di bawahnya
static const int DATE_Y = 42, BAR_Y = 56;
#else
static const char* const DAYS[7] = {"Min", "Sen", "Sel", "Rab", "Kam", "Jum", "Sab"};
// Digit ukuran 3: sel 18 x 24 px
static const int DIG_SIZE = 3, DIG_X = 2, DIG_Y = 4, DIG_CELL = 6 * DIG_SIZE;
static const int BAND_H = 32;
#endif

void ClockModule::enter() { _animAt = 0; }

bool ClockModule::input(Gesture g) {
  if (g != G_TAP) return false;
  _seconds = !_seconds;
  buzzer::play(MEL_TAP);
  return true;
}

// HH:MM besar; digit yang berubah meluncur ke atas (p = progres animasi 0..1)
void ClockModule::drawDigits(Adafruit_GFX& g, float p, uint32_t now) {
  g.setTextSize(DIG_SIZE);
  for (int i = 0; i < 5; i++) {
    int x = DIG_X + i * DIG_CELL;
    if (i == 2) {                                  // titik dua berkedip
      if ((now / 500) % 2 == 0) { g.setCursor(x, DIG_Y); g.print(':'); }
      continue;
    }
    if (p < 1.0f && _prev[i] != _shown[i]) {
      int off = (int)(p * BAND_H);
      g.setCursor(x, DIG_Y - off); g.print(_prev[i]);
      g.setCursor(x, DIG_Y + BAND_H - off); g.print(_shown[i]);
    } else {
      g.setCursor(x, DIG_Y); g.print(_shown[i]);
    }
  }
}

void ClockModule::render(Adafruit_GFX& g, uint32_t now) {
  struct tm t;
  bool ok = clockx::get(t);
  g.setTextColor(1);

  if (!ok) {
#if SCREEN_H >= 64
    g.setTextSize(DIG_SIZE); g.setCursor(DIG_X, DIG_Y); g.print("--:--");
    display::centerText("Jam belum diatur", DATE_Y);
    display::centerText("sambungkan aplikasi", BAR_Y - 2);
#else
    g.setTextSize(3); g.setCursor(2, 4); g.print("--:--");
    g.setTextSize(1); g.setCursor(96, 6); g.print("atur"); g.setCursor(96, 17); g.print("jam");
#endif
    return;
  }

#if SCREEN_H >= 64
  if (_seconds) {                                  // mode detik: HH:MM besar + SS di kanan bawah
    char hm[6], ss[3];
    snprintf(hm, sizeof(hm), "%02d:%02d", t.tm_hour, t.tm_min);
    snprintf(ss, sizeof(ss), "%02d", t.tm_sec);
    g.setTextSize(3); g.setCursor(6, 8); g.print(hm);
    g.setTextSize(2); g.setCursor(98, 15); g.print(ss);
    char d[24];
    snprintf(d, sizeof(d), "%s, %d %s %d", DAYS_LONG[t.tm_wday], t.tm_mday, MONTHS[t.tm_mon], t.tm_year + 1900);
    display::centerText(d, DATE_Y);
    return;
  }
#else
  if (_seconds) {                                  // mode detik: HH:MM:SS
    char b[10];
    snprintf(b, sizeof(b), "%02d:%02d:%02d", t.tm_hour, t.tm_min, t.tm_sec);
    g.setTextSize(2); g.setCursor(16, 9); g.print(b);
    return;
  }
#endif

  char cur[6];
  snprintf(cur, sizeof(cur), "%02d:%02d", t.tm_hour, t.tm_min);
  if (strcmp(cur, _shown) != 0) {                  // menit berganti -> mulai animasi
    memcpy(_prev, _shown, 6);
    memcpy(_shown, cur, 6);
    _animAt = now;
  }
  float p = 1.0f;
  if (_animAt) {
    uint32_t dt = now - _animAt;
    p = dt >= ANIM_MS ? 1.0f : (float)dt / ANIM_MS;
    p = 1 - (1 - p) * (1 - p);                     // ease-out
    if (dt >= ANIM_MS) _animAt = 0;
  }
  drawDigits(g, p, now);

#if SCREEN_H >= 64
  // Potong digit yang sedang meluncur, lalu baris tanggal dan bilah detik
  g.fillRect(0, BAND_H, SCREEN_W, SCREEN_H - BAND_H, 0);
  g.setTextSize(1);
  char d[24];
  snprintf(d, sizeof(d), "%s, %d %s %d", DAYS_LONG[t.tm_wday], t.tm_mday, MONTHS[t.tm_mon], t.tm_year + 1900);
  if (battery::charging() && (now / 3000) % 2) {          // mengisi: tanggal bergantian dengan "charging 78%"
    int cp = battery::percent();
    if (cp >= 0) snprintf(d, sizeof(d), "charging %d%%", cp);
    else strlcpy(d, "charging", sizeof(d));
  }
  display::centerText(d, DATE_Y);
  // Bilah detik; ikon baterai di ujung kanan jika baterai terbaca / sedang mengisi
  const int pct = battery::percent();
  const bool chg = battery::charging(), bat = pct >= 0 || chg;
  const int bw = SCREEN_W - 2 * DIG_X - (bat ? 19 : 0);
  g.drawRect(DIG_X, BAR_Y, bw, 4, 1);
  g.fillRect(DIG_X + 1, BAR_Y + 1, (t.tm_sec * (bw - 2)) / 59, 2, 1);
  if (bat && !(battery::low() && !chg && (now / 500) % 2))          // lemah: berkedip
    display::batteryIcon(SCREEN_W - DIG_X - 15, BAR_Y - 2, pct, chg, now);
#else
  // Kolom kanan: hari, tanggal, dan bilah detik
  g.fillRect(93, 0, 35, 32, 0);
  g.setTextSize(1);
  g.setCursor(97, 3); g.print(DAYS[t.tm_wday]);
  char d[8]; snprintf(d, sizeof(d), "%02d/%02d", t.tm_mday, t.tm_mon + 1);
  g.setCursor(96, 14); g.print(d);
  g.drawRect(96, 26, 30, 4, 1);
  g.fillRect(97, 27, (t.tm_sec * 28) / 59, 2, 1);
#endif
}
