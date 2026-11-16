#pragma once
#include <Arduino.h>
#include <Adafruit_GFX.h>

// Mesin wajah Lokana: sepasang mata prosedural. Ukuran mengikuti SCREEN_H (64 atau 32).
enum Expression : uint8_t {
  EXP_NEUTRAL, EXP_HAPPY, EXP_SAD, EXP_ANGRY, EXP_SLEEPY, EXP_SURPRISED,
  EXP_LOVE, EXP_DIZZY, EXP_SUSPICIOUS, EXP_BORED, EXP_EXCITED, EXP_NERVOUS, EXP_WINK,
  EXP_COUNT
};

const char* expressionName(Expression e);
bool expressionFromName(const char* s, Expression& out);

class Face {
public:
  void begin();
  void setExpression(Expression e, uint32_t holdMs = 0);
  Expression expression() const { return _exp; }
  bool holding() const { return _holding; }
  bool holdExpired(uint32_t now) const { return _holding && (int32_t)(now - _holdUntil) >= 0; }
  void lookAt(float x, float y) { _ltx = constrain(x, -1.f, 1.f); _lty = constrain(y, -1.f, 1.f); }
  void setAutoLook(bool on) { _autoLook = on; }
  void blink();
  void setOpen(float f) { _openT = f; }
  void setOpenNow(float f) { _open = _openT = f; }
  void update(uint32_t now);
  void draw(Adafruit_GFX& g, int16_t dx = 0);

  struct Shape { float w, h, r, lidTop[2], slant[2], lidBot[2], scale[2]; };

private:
  void drawEye(Adafruit_GFX& g, uint8_t i, float cx, float cy, float w, float h, float sc);
  static void heart(Adafruit_GFX& g, int cx, int cy, float s);
  static void drop(Adafruit_GFX& g, int x, int y, int r);
  static void spiral(Adafruit_GFX& g, int cx, int cy, float rmax, float ph);

  Expression _exp = EXP_NEUTRAL;
  Shape _cur{}, _tgt{};
  float _lx = 0, _ly = 0, _ltx = 0, _lty = 0;
  float _open = 1, _openT = 1, _blinkF = 1;
  bool _autoLook = true, _blinking = false, _holding = false;
  uint8_t _blinkRep = 0;
  int8_t _jx = 0;
  uint32_t _now = 0, _last = 0, _nextBlink = 0, _blinkAt = 0, _nextLook = 0, _holdUntil = 0, _since = 0;
};
