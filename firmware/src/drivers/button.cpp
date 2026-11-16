#include "button.h"
#include "config.h"

static bool rawLast = false, stable = false, longFired = false;
static uint32_t lastChange = 0, pressStart = 0, lastRelease = 0, lastAct = 0;
static uint8_t clicks = 0;

// Interrupt menangkap tap yang lebih singkat dari debounce / saat loop sibuk
static volatile bool edge = false;
static volatile uint32_t edgeAt = 0;
static void IRAM_ATTR onEdge() { edge = true; edgeAt = millis(); }

static bool readRaw() {
  int v = digitalRead(PIN_BTN);
  return BTN_ACTIVE_LOW ? (v == LOW) : (v == HIGH);
}

namespace button {

void begin() {
  pinMode(PIN_BTN, BTN_ACTIVE_LOW ? INPUT_PULLUP : INPUT_PULLDOWN);
  rawLast = stable = readRaw();
  attachInterrupt(digitalPinToInterrupt(PIN_BTN), onEdge, BTN_ACTIVE_LOW ? FALLING : RISING);
}

Gesture update(uint32_t now) {
  bool raw = readRaw();
  if (raw != rawLast) { rawLast = raw; lastChange = now; }

  if (now - lastChange >= BTN_DEBOUNCE_MS && raw != stable) {
    stable = raw;
    lastAct = now;
    if (stable) { pressStart = now; longFired = false; edge = false; }
    else if (!longFired) { clicks++; lastRelease = now; }
  }

  // tekanan sangat singkat yang lolos dari polling
  if (edge && !stable && !raw && (int32_t)(now - edgeAt) >= 5) {
    edge = false;
    if ((int32_t)(edgeAt - lastRelease) >= 60) { clicks++; lastRelease = now; lastAct = now; }
  }

  if (stable && !longFired && now - pressStart >= BTN_LONG_MS) {
    longFired = true;
    clicks = 0;
    return G_LONG;
  }
  if (!stable && clicks && now - lastRelease >= BTN_MULTI_MS) {
    uint8_t c = clicks;
    clicks = 0;
    return c == 1 ? G_TAP : c == 2 ? G_DOUBLE : G_TRIPLE;
  }
  return G_NONE;
}

bool pressed() { return stable || readRaw() || edge; }
uint32_t lastActivity() { return lastAct; }

const char* name(Gesture g) {
  switch (g) {
    case G_TAP: return "tap";
    case G_DOUBLE: return "double";
    case G_TRIPLE: return "triple";
    case G_LONG: return "long";
    default: return "none";
  }
}

}  // namespace button
