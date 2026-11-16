#include "splash_module.h"
#include <math.h>
#include "config.h"
#include "core/core.h"
#include "drivers/buzzer.h"
#include "core/settings.h"
#include "splash_art.h"

// ---------- Tata letak ----------
// Mata terpejam di akhir = posisi mata Face saat open 0.05 (lihat core/face.cpp), supaya
// perpindahan ke modul wajah mulus. Rentang x: [awal, akhir).
#if SCREEN_H >= 64
static const uint8_t* const ART = SPLASH64;
static const int AW = SPLASH64_W, AH = SPLASH64_H, LY0 = SPLASH64_LINE_Y0, LY1 = SPLASH64_LINE_Y1;
static const int WY = 7, TAG_Y = 48;
static const int EYE_Y = 28, EYE_H = 2, EYE_L0 = 19, EYE_L1 = 54, EYE_R0 = 74, EYE_R1 = 109;
#else
static const uint8_t* const ART = SPLASH32;
static const int AW = SPLASH32_W, AH = SPLASH32_H, LY0 = SPLASH32_LINE_Y0, LY1 = SPLASH32_LINE_Y1;
static const int WY = 5, TAG_Y = -1;                 // 32 px: tanpa tulisan LOKANA
static const int EYE_Y = 15, EYE_H = 2, EYE_L0 = 32, EYE_L1 = 56, EYE_R0 = 72, EYE_R1 = 96;
#endif
static const int WX = (SCREEN_W - AW) / 2, STRIDE = (AW + 7) / 8;
static const char TAG[] = "LOKANA";
static const int TAG_STEP = 10, TAG_X = (SCREEN_W - (5 * TAG_STEP + 5)) / 2;

// ---------- Linimasa (ms) ----------
enum : uint32_t {
  T_LINE = 150,    // garis atas tumbuh dari tengah
  T_DROP = 550,    // huruf turun dari garis, kiri ke kanan
  T_HOOK = 1150,   // matra ो muncul dari garis + nada boot
  T_TAG = 1450,    // LOKANA mengetik
  T_GLINT = 2000,  // kilau melintas
  T_OUT = 2900,    // huruf kembali ke garis
  T_EYES = 3250,   // garis terbelah jadi dua mata terpejam
  T_END = 3650,
};

static inline float clamp01(float v) { return v < 0 ? 0 : v > 1 ? 1 : v; }
static inline float phase(uint32_t t, uint32_t a, uint32_t b) { return clamp01((float)((int32_t)(t - a)) / (b - a)); }
static inline float easeOut(float p) { float q = 1 - p; return 1 - q * q * q; }
static inline float easeInOut(float p) { return p < 0.5f ? 4 * p * p * p : 1 - powf(-2 * p + 2, 3) / 2; }
static inline float easeOutBack(float p) { const float c = 1.7f; float q = p - 1; return 1 + (c + 1) * q * q * q + c * q * q; }
static inline bool artPixel(int x, int y) { return pgm_read_byte(&ART[y * STRIDE + (x >> 3)]) & (0x80 >> (x & 7)); }

void SplashModule::enter() {
  _t0 = millis();
  _sfx = 0;
}

uint32_t SplashModule::elapsed(uint32_t now) const { return _freeze ? _freeze : now - _t0; }

void SplashModule::finish() {
  _freeze = 0;
  _face.setOpenNow(0.05f);                         // mulai dari mata terpejam, sama dengan akhir splash
  _face.setOpen(1);
  _face.setExpression(EXP_HAPPY, 1500);
  bool boot = !_played;
  _played = true;
  core::goTo("Lokana");
  // Panduan cara pakai sesudah wajah bangun (hanya saat boot; batal jika Lokana disentuh dulu)
  if (boot && settings::get().bootGuide) core::goToLater("Panduan", 1800);
}

bool SplashModule::input(Gesture g) {
  (void)g;
  uint32_t now = millis();
  if (_freeze) finish();
  else if (elapsed(now) < T_OUT) { _t0 = now - T_OUT; _sfx = 2; }   // lewati: langsung ke penutup
  return true;
}

void SplashModule::event(const Event& e) {
  if (e.type != EV_SPLASH) return;
  _freeze = e.value > 0 ? (uint32_t)e.value : 0;
  core::goTo(name());
  enter();
}

void SplashModule::update(uint32_t now) {
  uint32_t t = elapsed(now);
  if (_freeze) return;
  if (_sfx == 0 && t >= T_LINE) { buzzer::play(MEL_TICK); _sfx = 1; }
  if (_sfx == 1 && t >= T_HOOK) { buzzer::play(MEL_BOOT); _sfx = 2; }
  if (t >= T_END) finish();
}

void SplashModule::render(Adafruit_GFX& g, uint32_t now) {
  uint32_t t = elapsed(now);
  if (t < T_LINE) return;

  // Mata terpejam: dua bagian garis bergeser ke posisi mata, menipis, dan saling menjauh
  if (t >= T_EYES) {
    float p = easeInOut(phase(t, T_EYES, T_END));
    const int mid = WX + AW / 2;
    int y = (int)roundf(WY + LY0 + (EYE_Y - WY - LY0) * p);
    int h = (int)roundf((LY1 - LY0 + 1) + (EYE_H - (LY1 - LY0 + 1)) * p);
    int l0 = (int)roundf(WX + (EYE_L0 - WX) * p), l1 = (int)roundf(mid + (EYE_L1 - mid) * p);
    int r0 = (int)roundf(mid + (EYE_R0 - mid) * p), r1 = (int)roundf(WX + AW + (EYE_R1 - WX - AW) * p);
    g.fillRoundRect(l0, y, l1 - l0, h, 1, 1);
    g.fillRoundRect(r0, y, r1 - r0, h, 1, 1);
    return;
  }

  // Keadaan tiap bagian tulisan pada waktu t
  float half = AW / 2.f * easeOut(phase(t, T_LINE, T_DROP));   // lebar garis atas (dari tengah)
  float drop = phase(t, T_DROP, T_HOOK);                       // huruf turun (gelombang kiri -> kanan)
  float down = 1;                                              // pengali kedalaman saat kembali
  float hook = t >= T_HOOK ? easeOutBack(phase(t, T_HOOK, T_TAG)) : 0;
  if (t >= T_OUT) {
    float p = easeInOut(phase(t, T_OUT, T_EYES));
    down = 1 - p;
    hook = 1 - p;
  }
  const int below = AH - 1 - LY1;
  int hookOff = (int)roundf((1 - hook) * LY0);                 // matra naik dari balik garis
  float glint = -1000;
  if (t >= T_GLINT && t < T_OUT) glint = -14 + (AW + 28) * phase(t, T_GLINT, T_GLINT + 550);

  for (int y = 0; y < AH; y++) {
    for (int x = 0; x < AW; x++) {
      if (!artPixel(x, y)) continue;
      int dy = 0;
      if (y < LY0) {                                           // matra di atas garis
        dy = hookOff;
        if (y + dy >= LY0 || hook <= 0) continue;
      } else if (y <= LY1) {                                   // garis atas
        if (fabsf(x + 0.5f - AW / 2.f) > half) continue;
      } else {                                                 // badan huruf
        float d = easeOut(clamp01((drop - 0.35f * x / AW) / 0.65f)) * down;
        if (y - LY1 > d * below) continue;
      }
      float gx = x - (y + dy) * 0.5f - glint;                  // pita kilau miring
      if (gx >= 0 && gx < 4) continue;
      g.drawPixel(WX + x, WY + y + dy, 1);
    }
  }

  // LOKANA mengetik per huruf, hilang saat penutup
  if (TAG_Y >= 0 && t >= T_TAG) {
    int n = min(6, (int)((t - T_TAG) / 70) + 1);
    if (t >= T_OUT) n = max(0, 6 - (int)((t - T_OUT) / 40));
    g.setTextSize(1);
    g.setTextColor(1);
    for (int i = 0; i < n; i++) {
      uint32_t age = t - T_TAG - i * 70;
      g.setCursor(TAG_X + i * TAG_STEP, TAG_Y + (t < T_OUT && age < 60 ? 2 : 0));
      g.print(TAG[i]);
    }
  }
}
