#include "settings.h"
#include <Preferences.h>

const uint32_t SCREEN_TIMEOUT_MS[SCREEN_TIMEOUT_COUNT] = {15000UL, 30000UL, 60000UL, 300000UL, 0UL};
const char* const SCREEN_TIMEOUT_LABEL[SCREEN_TIMEOUT_COUNT] = {"15 dtk", "30 dtk", "1 mnt", "5 mnt", "Tidak"};
const char* const BRIGHTNESS_LABEL[3] = {"Redup", "Sedang", "Terang"};

static Settings s;
static Preferences prefs;

namespace settings {

Settings& get() { return s; }

void load() {
  prefs.begin("lokana", true);
  s.brightness = min<uint8_t>(prefs.getUChar("bright", 1), 2);
  s.sound      = prefs.getBool("sound", true);
  s.screenIdx  = min<uint8_t>(prefs.getUChar("screen", 2), SCREEN_TIMEOUT_COUNT - 1);
  s.flip       = prefs.getBool("flip", false);
  s.tzMin      = constrain(prefs.getShort("tz", TZ_OFFSET_MIN), -720, 840);
  prefs.getString("name", s.name, sizeof(s.name));
  s.notifPopupS = clampNotifPopup(prefs.getUChar("npop", 6));
  s.bootGuide  = prefs.getBool("guide", true);
  prefs.end();
}

void save() {
  prefs.begin("lokana", false);
  prefs.putUChar("bright", s.brightness);
  prefs.putBool("sound", s.sound);
  prefs.putUChar("screen", s.screenIdx);
  prefs.putBool("flip", s.flip);
  prefs.putShort("tz", s.tzMin);
  prefs.putString("name", s.name);
  prefs.putUChar("npop", s.notifPopupS);
  prefs.putBool("guide", s.bootGuide);
  prefs.end();
}

void reset() { s = Settings(); save(); }

uint8_t clampNotifPopup(uint8_t v) { return v == 0 ? 0 : constrain(v, 3, 60); }

uint32_t screenTimeoutMs() { return SCREEN_TIMEOUT_MS[s.screenIdx]; }
uint16_t screenTimeoutS() { return SCREEN_TIMEOUT_MS[s.screenIdx] / 1000; }

void setScreenTimeoutS(uint16_t sec) {
  if (sec == 0) { s.screenIdx = SCREEN_TIMEOUT_COUNT - 1; return; }   // tidak pernah mati
  uint8_t best = 0;
  uint32_t bestD = UINT32_MAX;
  for (uint8_t i = 0; i < SCREEN_TIMEOUT_COUNT; i++) {
    if (!SCREEN_TIMEOUT_MS[i]) continue;
    uint32_t v = SCREEN_TIMEOUT_MS[i] / 1000, d = v > sec ? v - sec : sec - v;
    if (d < bestD) { bestD = d; best = i; }
  }
  s.screenIdx = best;
}

}  // namespace settings
