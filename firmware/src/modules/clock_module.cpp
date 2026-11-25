#include "clock_module.h"
#include "config.h"
#include "core/clock.h"
#include "core/settings.h"
#include "drivers/buzzer.h"
#include "drivers/display.h"
#include "drivers/hw.h"
#include <esp_system.h>

static const uint16_t ANIM_MS = 350;
static volatile bool demoReq = false;      // console `jam anim`

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

// Pola angka 0-9 font classic 5x7 (glcdfont Adafruit GFX, BSD): 5 kolom, bit 0 = baris atas.
// Sama persis dengan angka Klasik (print ukuran 4), dipakai gaya yang menggambar angka sendiri.
static const uint8_t DIGIT_COLS[10][5] = {
  {0x3E, 0x51, 0x49, 0x45, 0x3E}, {0x00, 0x42, 0x7F, 0x40, 0x00}, {0x72, 0x49, 0x49, 0x49, 0x46},
  {0x21, 0x41, 0x49, 0x4D, 0x33}, {0x18, 0x14, 0x12, 0x7F, 0x10}, {0x27, 0x45, 0x45, 0x45, 0x39},
  {0x3C, 0x4A, 0x49, 0x49, 0x31}, {0x41, 0x21, 0x11, 0x09, 0x07}, {0x36, 0x49, 0x49, 0x49, 0x36},
  {0x46, 0x49, 0x49, 0x29, 0x1E},
};

static inline bool lit(char c, int col, int row) {
  return c >= '0' && c <= '9' && (DIGIT_COLS[c - '0'][col] >> row & 1);
}

// Angka dari pola 5x7: sel `cell` px, jarak sel `pitch` px. f = bukaan vertikal (1 penuh, 0 terpejam jadi garis).
static void glyph(Adafruit_GFX& g, char c, int x, int y, int cell, int pitch, float f = 1.0f) {
  const float cy = y + 3.5f * pitch;
  if (f < 0.12f) {                                 // terpejam: garis kelopak
    if (c >= '0' && c <= '9') g.fillRect(x, (int)cy - 1, 4 * pitch + cell, 2, 1);
    return;
  }
  const int h = max(1, (int)(cell * f + 0.5f));
  for (int col = 0; col < 5; col++)
    for (int row = 0; row < 7; row++)
      if (lit(c, col, row)) {
        const float mid = cy + (row * pitch + cell * 0.5f - 3.5f * pitch) * f;
        g.fillRect(x + col * pitch, (int)(mid - h * 0.5f + 0.5f), cell, h, 1);
      }
}

static float easeOut(float p) { return 1 - (1 - p) * (1 - p); }
static float clamp01(float v) { return v < 0 ? 0 : v > 1 ? 1 : v; }

void ClockModule::demoAnim() { demoReq = true; }

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

#if SCREEN_H >= 64
// Bawah layar (Klasik, Kubus, Kedip): potong animasi di atas clipY, tanggal (bergantian "charging"), bilah detik
// opsional, ikon baterai
void ClockModule::drawFooter(Adafruit_GFX& g, const struct tm& t, uint32_t now, bool bar) {
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
  if (bar) {
    g.drawRect(DIG_X, BAR_Y, bw, 4, 1);
    g.fillRect(DIG_X + 1, BAR_Y + 1, (t.tm_sec * (bw - 2)) / 59, 2, 1);
  }
  if (bat && !(battery::low() && !chg && (now / 500) % 2))          // lemah: berkedip
    display::batteryIcon(SCREEN_W - DIG_X - 15, BAR_Y - 2, pct, chg, now);
}

// ---------------- Mata: mata Lokana menjemput angka ----------------
static const uint16_t EYES_MS = 1400;
static const int E_DX = 19, E_CELL = 18, E_Y = 3;          // angka ukuran 3 (sel 18 px), mulai x 19
static const int EYE_W = 26, EYE_H = 22, EYE_R = 7, EYE_GAP = 21, EYE_CY = 46;

void ClockModule::renderEyes(Adafruit_GFX& g, const struct tm& t, uint32_t now) {
  int32_t el = _animAt ? (int32_t)(now - _animAt) : EYES_MS;
  if (el < 0) el = 0;
  if (el >= EYES_MS) _animAt = 0;
  // Angka: yang lama tenggelam ke arah mata (0-500 ms), yang baru jatuh dari atas (300-800 ms)
  const float sink = easeOut(clamp01(el / 500.0f)), drop = easeOut(clamp01((el - 300) / 500.0f));
  int changed = 0, changedX = 0;
  for (int i = 0; i < 5; i++) {
    const int x = E_DX + i * E_CELL;
    if (i == 2) continue;                          // titik dua digambar di bawah
    if (el < EYES_MS && _prev[i] != _shown[i]) {
      changed++;
      changedX += x + 7;
      if (sink < 1) glyph(g, _prev[i], x, E_Y + (int)(sink * 26), 3, 3);
      if (el >= 300) glyph(g, _shown[i], x, E_Y - (int)((1 - drop) * 26), 3, 3);
    } else {
      glyph(g, _shown[i], x, E_Y, 3, 3);
    }
  }
  if ((now / 500) % 2 == 0) {                      // titik dua: dua kotak 3x3
    g.fillRect(E_DX + 2 * E_CELL + 6, E_Y + 6, 3, 3, 1);
    g.fillRect(E_DX + 2 * E_CELL + 6, E_Y + 15, 3, 3, 1);
  }
  g.fillRect(0, 26, SCREEN_W, SCREEN_H - 26, 0);  // angka lama "masuk" ke bawah, terpotong di sini

  // Lirikan: biasanya mengikuti detik kiri -> kanan; saat menit berganti melirik ke atas ke angka yang berubah
  float tx = t.tm_sec / 59.0f * 2 - 1, ty = 0.15f;
  if (el < 900 && changed) { tx = (changedX / (float)changed - SCREEN_W / 2) / 45.0f; ty = -1; }
  _lookX += (constrain(tx, -1.f, 1.f) - _lookX) * 0.18f;
  _lookY += (ty - _lookY) * 0.25f;
  // Kedip acak 2,5-6 dtk, 160 ms
  if (!_nextBlink || (int32_t)(now - _nextBlink) >= 0) {
    _blinkAt = now;
    _nextBlink = now + 2500 + esp_random() % 3500;
  }
  const int32_t bt = (int32_t)(now - _blinkAt);
  const float open = bt >= 0 && bt < 160 ? fabsf(1 - bt / 80.0f) : 1.0f;
  const bool happy = el >= 800 && el < EYES_MS && changed;   // senyum setelah angka mendarat
  const int ih = max(2, (int)(EYE_H * open + 0.5f));
  for (int e = 0; e < 2; e++) {
    const int cx = SCREEN_W / 2 + (e ? EYE_GAP : -EYE_GAP) + (int)(_lookX * 9);
    const int cy = EYE_CY + (int)(_lookY * 4);
    const int x0 = cx - EYE_W / 2, y0 = cy - ih / 2;
    g.fillRoundRect(x0, y0, EYE_W, ih, min(EYE_R, ih / 2), 1);
    if (happy) {                                   // pipi naik -> mata senyum
      const int by = y0 + ih - (int)(0.45f * ih);
      g.fillRoundRect(x0 - 3, by, EYE_W + 6, ih + 4, min((EYE_W + 6) / 2 - 1, (ih + 4) / 2), 0);
    }
  }
  const int pct = battery::percent();
  const bool chg = battery::charging();
  if ((pct >= 0 || chg) && !(battery::low() && !chg && (now / 500) % 2))
    display::batteryIcon(SCREEN_W - 17, SCREEN_H - 9, pct, chg, now);
}

// ---------------- Kubus: angka dari kubus 4x4 yang jatuh & menumpuk ----------------
static const uint16_t CUBES_MS = 1600;
static const int C_PITCH = 5, C_CELL = 4, C_Y = 3;
static const int C_X[5] = {7, 34, 62, 70, 97};    // H, H, titik dua, M, M (lebar angka 24 px)
static const float C_G = 0.0012f;                  // gravitasi, px/ms^2

static uint32_t cubeHash(int i, int c, int r) { return (uint32_t)(i * 31 + c * 7 + r * 13 + 1) * 2654435761u >> 24; }

void ClockModule::renderCubes(Adafruit_GFX& g, const struct tm& t, uint32_t now) {
  int32_t el = _animAt ? (int32_t)(now - _animAt) : CUBES_MS;
  if (el < 0) el = 0;
  if (el >= CUBES_MS) _animAt = 0;
  for (int i = 0; i < 5; i++) {
    if (i == 2) {
      if ((now / 500) % 2 == 0) {
        g.fillRect(C_X[2], C_Y + 2 * C_PITCH, C_CELL, C_CELL, 1);
        g.fillRect(C_X[2], C_Y + 4 * C_PITCH, C_CELL, C_CELL, 1);
      }
      continue;
    }
    const bool anim = el < CUBES_MS && _prev[i] != _shown[i];
    for (int c = 0; c < 5; c++)
      for (int r = 0; r < 7; r++) {
        const int x = C_X[i] + c * C_PITCH, ty = C_Y + r * C_PITCH;
        if (!anim) {
          if (lit(_shown[i], c, r)) g.fillRect(x, ty, C_CELL, C_CELL, 1);
          continue;
        }
        if (lit(_prev[i], c, r)) {                 // kubus lama jatuh keluar, tiap kubus mulai sedikit berbeda
          const float tt = el - (float)(cubeHash(i, c, r) % 250);
          const int y = tt <= 0 ? ty : ty + (int)(0.5f * C_G * tt * tt);
          if (y < BAND_H + 4) g.fillRect(x, y, C_CELL, C_CELL, 1);
        }
        if (lit(_shown[i], c, r)) {                // kubus baru: baris bawah dulu, jatuh dari atas, memantul kecil
          const float d = 350 + (6 - r) * 110 + c * 20;
          const float dist = ty + 6;
          const float fall = sqrtf(2 * dist / C_G);
          const float tt = el - d;
          if (tt < 0) continue;
          int y;
          if (tt < fall) y = -6 + (int)(0.5f * C_G * tt * tt);
          else if (tt < fall + 140) y = ty - (int)(2.5f * sinf(PI * (tt - fall) / 140));
          else y = ty;
          g.fillRect(x, y, C_CELL, C_CELL, 1);
        }
      }
  }
}

// ---------------- Kedip: angka yang berkedip seperti mata ----------------
static const uint16_t BLINK_MS = 360, IDLE_BLINK_MS = 260;

void ClockModule::renderBlink(Adafruit_GFX& g, const struct tm& t, uint32_t now) {
  int32_t el = _animAt ? (int32_t)(now - _animAt) : BLINK_MS;
  if (el < 0) el = 0;
  if (el >= BLINK_MS) _animAt = 0;
  // Kedip sendiri tiap 3-7 dtk: satu angka, atau (30%) semuanya sekaligus seperti dua mata
  if (!_nextBlink || (int32_t)(now - _nextBlink) >= 0) {
    _blinkAt = now;
    _nextBlink = now + 3000 + esp_random() % 4000;
    static const uint8_t IDX[4] = {0, 1, 3, 4};
    _blinkDigit = esp_random() % 10 < 3 ? 255 : IDX[esp_random() % 4];
  }
  const int32_t bt = (int32_t)(now - _blinkAt);
  const float idle = bt >= 0 && bt < IDLE_BLINK_MS ? fabsf(1 - bt / (IDLE_BLINK_MS / 2.0f)) : 1.0f;
  for (int i = 0; i < 5; i++) {
    const int x = DIG_X + i * DIG_CELL;
    if (i == 2) {
      if ((now / 500) % 2 == 0) { g.setTextSize(DIG_SIZE); g.setCursor(x, DIG_Y); g.print(':'); }
      continue;
    }
    if (el < BLINK_MS && _prev[i] != _shown[i]) {  // memejam sebagai angka lama, membuka sebagai angka baru
      const int half = BLINK_MS / 2;
      if (el < half) glyph(g, _prev[i], x, DIG_Y, 4, 4, 1 - el / (float)half);
      else glyph(g, _shown[i], x, DIG_Y, 4, 4, (el - half) / (float)half);
    } else {
      glyph(g, _shown[i], x, DIG_Y, 4, 4, (_blinkDigit == 255 || _blinkDigit == i) ? idle : 1.0f);
    }
  }
}
#endif

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
  if (demoReq) {                                   // console `jam anim`: seolah menit sebelumnya baru lewat
    demoReq = false;
    int m = t.tm_hour * 60 + t.tm_min - 1;
    if (m < 0) m += 24 * 60;
    snprintf(_shown, sizeof(_shown), "%02d:%02d", m / 60, m % 60);
  }
  if (strcmp(cur, _shown) != 0) {                  // menit berganti -> mulai animasi
    memcpy(_prev, _shown, 6);
    memcpy(_shown, cur, 6);
    _animAt = now ? now : 1;
  }

#if SCREEN_H >= 64
  const uint8_t style = settings::get().clockStyle;
  if (style != _style) { _style = style; _nextBlink = 0; }
  switch (style) {
    case 1: renderEyes(g, t, now); return;
    case 2: renderCubes(g, t, now); drawFooter(g, t, now, true); return;
    case 3: renderBlink(g, t, now); drawFooter(g, t, now, true); return;
    default: break;
  }
#endif

  float p = 1.0f;
  if (_animAt) {
    int32_t dt = (int32_t)(now - _animAt);
    if (dt < 0) dt = 0;
    p = dt >= ANIM_MS ? 1.0f : (float)dt / ANIM_MS;
    p = 1 - (1 - p) * (1 - p);                     // ease-out
    if (dt >= ANIM_MS) _animAt = 0;
  }
  drawDigits(g, p, now);

#if SCREEN_H >= 64
  drawFooter(g, t, now, true);                     // potong digit yang sedang meluncur, tanggal, bilah detik
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
