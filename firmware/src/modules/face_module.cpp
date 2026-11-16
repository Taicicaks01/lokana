#include "face_module.h"
#include "drivers/buzzer.h"

static inline uint32_t since(uint32_t t, uint32_t now) { return (int32_t)(now - t) > 0 ? now - t : 0; }

void FaceModule::enter() {
  uint32_t now = millis();
  if (!_started) {                       // animasi bangun saat pertama kali tampil
    _face.begin();
    _face.setOpenNow(0.05f);
    _face.setOpen(1);
    _face.setExpression(EXP_HAPPY, 1500);
    _started = true;
  }
  _lastTouch = now;
  _nextIdle = now + random(4000, 8000);
}

Expression FaceModule::baseline(uint32_t now) const {
  return since(_lastTouch, now) > 60000UL ? EXP_BORED : EXP_NEUTRAL;
}

bool FaceModule::input(Gesture g) {
  if (g != G_TAP) return false;          // tahan -> Core mematikan layar
  uint32_t now = millis();
  _lastTouch = now;
  if (since(_pokeWindow, now) > 4000) { _pokes = 0; _pokeWindow = now; }
  _pokes++;
  _face.blink();
  if (_pokes >= 6) {
    _face.setExpression(EXP_ANGRY, 3000); buzzer::play(MEL_ANGRY); _pokes = 0;
  } else if (_pokes >= 4) {
    _face.setExpression(EXP_SUSPICIOUS, 1800); buzzer::play(MEL_TAP);
  } else {
    static const Expression R[] = {EXP_HAPPY, EXP_LOVE, EXP_WINK, EXP_EXCITED, EXP_SURPRISED};
    Expression e = R[random(5)];
    _face.setExpression(e, 1800);
    buzzer::play(e == EXP_LOVE ? MEL_LOVE : e == EXP_HAPPY ? MEL_HAPPY : MEL_TAP);
  }
  return true;
}

void FaceModule::event(const Event& e) {
  if (e.type == EV_EXPRESSION) {
    _lastTouch = millis();
    uint32_t hold = (uint32_t)e.value >> 8;
    _face.setExpression((Expression)(e.value & 0xFF), hold ? hold : 4000);
  }
}

void FaceModule::pickIdle(uint32_t now) {
  struct W { Expression e; uint8_t w; };
  static const W ACTIVE[] = {{EXP_NEUTRAL, 50}, {EXP_HAPPY, 15}, {EXP_SUSPICIOUS, 8}, {EXP_WINK, 5},
                             {EXP_SURPRISED, 5}, {EXP_LOVE, 5}, {EXP_EXCITED, 4}, {EXP_NERVOUS, 4}, {EXP_SAD, 4}};
  static const W BORED[]  = {{EXP_NEUTRAL, 35}, {EXP_BORED, 25}, {EXP_SLEEPY, 20}, {EXP_SUSPICIOUS, 10},
                             {EXP_SAD, 5}, {EXP_HAPPY, 5}};
  bool bored = since(_lastTouch, now) > 60000UL;
  const W* t = bored ? BORED : ACTIVE;
  uint8_t n = bored ? 6 : 9;
  int total = 0;
  for (uint8_t i = 0; i < n; i++) total += t[i].w;
  int r = random(total);
  Expression pick = t[0].e;
  for (uint8_t i = 0; i < n; i++) { if (r < t[i].w) { pick = t[i].e; break; } r -= t[i].w; }
  if (pick == EXP_NEUTRAL || pick == baseline(now)) _face.setExpression(baseline(now));
  else _face.setExpression(pick, random(2000, 4500));
  _nextIdle = now + random(5000, 12000);
}

void FaceModule::update(uint32_t now) {
  if (_face.holdExpired(now)) { _face.setExpression(baseline(now)); _nextIdle = now + random(4000, 9000); }
  if (!_face.holding() && (int32_t)(now - _nextIdle) >= 0) pickIdle(now);
  _face.update(now);
}

void FaceModule::render(Adafruit_GFX& g, uint32_t now) {
  (void)now;
  _face.draw(g);
}
