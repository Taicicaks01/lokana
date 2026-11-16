#include "face.h"
#include <math.h>
#include "config.h"

static const char* NAMES[EXP_COUNT] = {
  "netral", "senang", "sedih", "marah", "ngantuk", "kaget",
  "cinta", "pusing", "curiga", "bosan", "semangat", "gugup", "kedip"
};
static const char* ALIAS[EXP_COUNT] = {
  "neutral", "happy", "sad", "angry", "sleepy", "surprised",
  "love", "dizzy", "suspicious", "bored", "excited", "nervous", "wink"
};

const char* expressionName(Expression e) { return e < EXP_COUNT ? NAMES[e] : "?"; }

bool expressionFromName(const char* s, Expression& out) {
  for (uint8_t i = 0; i < EXP_COUNT; i++)
    if (!strcasecmp(s, NAMES[i]) || !strcasecmp(s, ALIAS[i])) { out = (Expression)i; return true; }
  return false;
}

// ---------- Geometri per ukuran layar ----------
// Preset di bawah ditulis untuk tinggi 32 px, lalu diskalakan (SX lebar, SY tinggi).
// 128x64: mata lebih tinggi, digeser sedikit ke atas supaya ada ruang efek di bawah.
#if SCREEN_H >= 64
static const float SX = 1.45f, SY = 1.6f;
static const float GAP = 20.f, CY = 29.f;      // jarak antar mata, pusat vertikal mata
static const float LOOK_X = 16.f, LOOK_Y = 6.f; // jangkauan lirikan
#else
static const float SX = 1.f, SY = 1.f;
static const float GAP = 16.f, CY = 16.f;
static const float LOOK_X = 28.f, LOOK_Y = 3.f;
#endif

// Bentuk mata per ekspresi (nilai dasar untuk tinggi 32 px)
static Face::Shape preset(Expression e) {
  Face::Shape p;
  p.w = 24; p.h = 26; p.r = 7;
  for (int i = 0; i < 2; i++) { p.lidTop[i] = 0; p.slant[i] = 0; p.lidBot[i] = 0; p.scale[i] = 1; }
  switch (e) {
    case EXP_HAPPY:      p.w = 26; p.h = 24; p.r = 9; p.lidBot[0] = p.lidBot[1] = 0.55f; break;
    case EXP_SAD:        p.h = 22; p.lidTop[0] = p.lidTop[1] = 0.30f; p.slant[0] = p.slant[1] = -0.6f; break;
    case EXP_ANGRY:      p.h = 22; p.r = 5; p.lidTop[0] = p.lidTop[1] = 0.25f; p.slant[0] = p.slant[1] = 0.8f; break;
    case EXP_SLEEPY:     p.w = 26; p.lidTop[0] = p.lidTop[1] = 0.62f; p.slant[0] = p.slant[1] = -0.15f; break;
    case EXP_SURPRISED:  p.w = 20; p.h = 30; p.r = 10; break;
    case EXP_SUSPICIOUS: p.lidTop[0] = 0.5f; p.lidTop[1] = 0.18f; p.slant[0] = 0.25f; p.slant[1] = 0.1f; p.scale[0] = 0.92f; break;
    case EXP_BORED:      p.w = 28; p.r = 4; p.lidTop[0] = p.lidTop[1] = 0.5f; break;
    case EXP_EXCITED:    p.w = 28; p.h = 28; p.r = 9; p.lidBot[0] = p.lidBot[1] = 0.5f; break;
    case EXP_NERVOUS:    p.w = 20; p.h = 22; p.lidTop[0] = p.lidTop[1] = 0.12f; p.slant[0] = p.slant[1] = -0.35f; break;
    case EXP_WINK:       p.lidBot[1] = 0.6f; p.lidTop[1] = 0.15f; break;
    default: break;
  }
  p.w *= SX; p.h *= SY; p.r *= SX;
  return p;
}

static inline float lerpf(float a, float b, float k) { return a + (b - a) * k; }

void Face::begin() {
  _cur = _tgt = preset(EXP_NEUTRAL);
  _nextBlink = millis() + 2000;
}

void Face::setExpression(Expression e, uint32_t holdMs) {
  if (e >= EXP_COUNT) return;
  uint32_t now = millis();
  if (e != _exp) _since = now;
  _exp = e;
  _tgt = preset(e);
  _holding = holdMs > 0;
  _holdUntil = now + holdMs;
}

void Face::blink() { if (!_blinking) { _blinking = true; _blinkAt = millis(); } }

void Face::update(uint32_t now) {
  uint32_t dt = _last ? now - _last : 16;
  if (dt > 100) dt = 100;
  _last = now; _now = now;
  float k = 1 - expf(-(float)dt / 70.f), kl = 1 - expf(-(float)dt / 45.f), ko = 1 - expf(-(float)dt / 120.f);
  _cur.w = lerpf(_cur.w, _tgt.w, k); _cur.h = lerpf(_cur.h, _tgt.h, k); _cur.r = lerpf(_cur.r, _tgt.r, k);
  for (int i = 0; i < 2; i++) {
    _cur.lidTop[i] = lerpf(_cur.lidTop[i], _tgt.lidTop[i], k);
    _cur.slant[i]  = lerpf(_cur.slant[i], _tgt.slant[i], k);
    _cur.lidBot[i] = lerpf(_cur.lidBot[i], _tgt.lidBot[i], k);
    _cur.scale[i]  = lerpf(_cur.scale[i], _tgt.scale[i], k);
  }
  _lx = lerpf(_lx, _ltx, kl); _ly = lerpf(_ly, _lty, kl); _open = lerpf(_open, _openT, ko);

  // Kedip otomatis
  bool canBlink = _exp != EXP_DIZZY && _exp != EXP_LOVE;
  if (canBlink && !_blinking && (int32_t)(now - _nextBlink) >= 0) {
    _blinking = true; _blinkAt = now;
    if (random(100) < 18) _blinkRep = 1;
  }
  if (_blinking) {
    int32_t bt = (int32_t)(now - _blinkAt);
    float t = (bt > 0 ? bt : 0) / 160.f;
    if (t >= 1) {
      _blinking = false; _blinkF = 1;
      if (_blinkRep) { _blinkRep--; _nextBlink = now + 90; }
      else _nextBlink = now + random(2200, 6000);
    } else _blinkF = max(0.08f, fabsf(cosf(PI * t)));
  }

  // Lirikan otomatis
  if (_autoLook && (int32_t)(now - _nextLook) >= 0) {
    if (random(100) < 45) { _ltx = 0; _lty = 0; }
    else { _ltx = random(-100, 101) / 100.f; _lty = random(-60, 61) / 100.f; }
    _nextLook = now + random(1200, 4200);
  }

  _jx = 0;
  if ((_exp == EXP_ANGRY && (int32_t)(now - _since) < 500) || _exp == EXP_NERVOUS) _jx = random(-1, 2);
}

void Face::draw(Adafruit_GFX& g, int16_t dx) {
  float bounce = (_exp == EXP_EXCITED) ? sinf(_now / 90.f) * 2.f * SY : 0;
  float lx = _lx * LOOK_X + _jx + dx, ly = _ly * LOOK_Y;
  float ecx[2], ecy[2], ew[2], eh[2];

  for (uint8_t i = 0; i < 2; i++) {
    float dir = i == 0 ? -1.f : 1.f;
    float sc = _cur.scale[i] * (1.f + dir * _lx * 0.08f);
    ew[i] = _cur.w * sc;
    eh[i] = _cur.h * sc * _open * _blinkF;
    ecx[i] = SCREEN_W / 2.f + dir * (GAP / 2 + _cur.w / 2) + lx;
    ecy[i] = CY + ly + bounce;
    if (_exp == EXP_LOVE) heart(g, (int)ecx[i], (int)ecy[i], (9.f + sinf(_now / 150.f)) * SX * _open);
    else if (_exp == EXP_DIZZY) spiral(g, (int)ecx[i], (int)ecy[i], 11.f * SY * _open, dir * _now / 120.f);
    else drawEye(g, i, ecx[i], ecy[i], ew[i], eh[i], sc);
  }

  // ---------- Aksen ----------
  g.setTextColor(1);
  if (_exp == EXP_SLEEPY) {                               // z kecil lalu Z besar melayang ke atas kanan
#if SCREEN_H >= 64
    uint16_t ph = (_now / 60) % 36;
    g.setTextSize(1); g.setCursor(108 + ph / 9, 24 - ph / 2); g.print('z');
    g.setTextSize(2); g.setCursor(112 + ph / 12, 12 - ph / 3); g.print('Z');
    g.setTextSize(1);
#else
    uint16_t ph = (_now / 70) % 24;
    g.setTextSize(1);
    g.setCursor(112 + ph / 8, 14 - ph / 2); g.print('z');
    g.setCursor(119 + ph / 10, 6 - ph / 3); g.print('Z');
#endif
  }
  const int dropR = SCREEN_H >= 64 ? 3 : 2;
  if (_exp == EXP_SAD && _open > 0.5f) {                  // air mata jatuh di sisi luar mata kiri
    const int top = SCREEN_H * 5 / 16, span = SCREEN_H - top - 4;
    int x = (int)(ecx[0] - ew[0] / 2 - 2 * dropR), y = top + (int)((_now / 40) % span);
    if (x > dropR && y < SCREEN_H - dropR) drop(g, x, y, dropR);
  }
  if (_exp == EXP_NERVOUS) {                              // keringat di sisi luar mata kanan
    int x = (int)(ecx[1] + ew[1] / 2 + 3 + dropR), y = SCREEN_H / 5 + (int)((_now / 60) % (SCREEN_H / 5));
    if (x < SCREEN_W - dropR - 1) drop(g, x, y, dropR);
  }
  if ((_exp == EXP_HAPPY || _exp == EXP_LOVE || _exp == EXP_EXCITED) && _open > 0.6f) {
    for (uint8_t i = 0; i < 2; i++) {                     // pipi merona: 3 garis miring
#if SCREEN_H >= 64
      // di bawah sisi luar mata (mata senyum menyisakan ruang di bawahnya)
      const int len = 4, step = 5, w = 2 * step + len;
      int x0 = (int)(i == 0 ? ecx[i] - ew[i] / 2 - 1 : ecx[i] + ew[i] / 2 + 1 - w);
      int y0 = (int)(ecy[i] + _cur.h * 0.28f);
#else
      const int len = 3, step = 4;
      int x0 = (int)(ecx[i] + (i == 0 ? -ew[i] / 2 - 12 : ew[i] / 2 + 3));
      int y0 = 27;
#endif
      if (x0 < 0 || x0 > SCREEN_W - 2 * step - len) continue;
      for (int s = 0; s < 3; s++) g.drawLine(x0 + s * step, y0, x0 + s * step + len - 1, y0 - len, 1);
    }
  }
}

void Face::drop(Adafruit_GFX& g, int x, int y, int r) {
  g.fillCircle(x, y, r, 1);
  g.fillTriangle(x - r, y, x + r, y, x, y - 2 * r, 1);
}

void Face::drawEye(Adafruit_GFX& g, uint8_t i, float cx, float cy, float w, float h, float sc) {
  int iw = max(4, (int)roundf(w)), ih = max(2, (int)roundf(h));
  int x0 = (int)roundf(cx - w / 2), y0 = (int)roundf(cy - h / 2);
  int r = min((int)roundf(_cur.r * sc), min(ih / 2, iw / 2));
  g.fillRoundRect(x0, y0, iw, ih, r, 1);

  float lt = _cur.lidTop[i], sl = _cur.slant[i];
  if (lt > 0.01f || fabsf(sl) > 0.01f) {                  // kelopak atas miring
    float base = y0 + lt * ih, half = sl * ih * 0.5f;
    int yIn = (int)(base + half), yOut = (int)(base - half);
    int yL = i == 0 ? yOut : yIn, yR = i == 0 ? yIn : yOut;
    int top = y0 - 2, xl = x0 - 1, xr = x0 + iw;
    g.fillTriangle(xl, top, xr, top, xl, yL, 0);
    g.fillTriangle(xr, top, xr, yR, xl, yL, 0);
  }
  float lb = _cur.lidBot[i];
  if (lb > 0.01f) {                                       // pipi bawah -> mata senyum
    int by = (int)(y0 + ih - lb * ih), bw = iw + 6;
    g.fillRoundRect(x0 - 3, by, bw, ih + 4, min(bw / 2 - 1, (ih + 4) / 2), 0);
  }
}

void Face::heart(Adafruit_GFX& g, int cx, int cy, float s) {
  int r = max(2, (int)(s * 0.5f));
  g.fillCircle(cx - r, cy - r / 2, r, 1);
  g.fillCircle(cx + r, cy - r / 2, r, 1);
  g.fillTriangle(cx - 2 * r, cy - r / 2, cx + 2 * r, cy - r / 2, cx, cy + (int)(1.7f * r), 1);
}

void Face::spiral(Adafruit_GFX& g, int cx, int cy, float rmax, float ph) {
  const float T = 5.f * PI;
  float px = cx, py = cy;
  for (float a = 0.4f; a < T; a += 0.4f) {
    float r = rmax * a / T, x = cx + cosf(a + ph) * r, y = cy + sinf(a + ph) * r;
    g.drawLine((int)px, (int)py, (int)x, (int)y, 1);
    g.drawLine((int)px + 1, (int)py, (int)x + 1, (int)y, 1);
    px = x; py = y;
  }
}
