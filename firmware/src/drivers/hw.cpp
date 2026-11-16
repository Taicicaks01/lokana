#include "hw.h"
#include "config.h"

// ---------------- LED (aktif LOW di Super Mini) ----------------
static uint32_t ledOffAt = 0;
static bool ledOn = false;

namespace led {
void begin() {
#if PIN_LED >= 0
  pinMode(PIN_LED, OUTPUT);
  digitalWrite(PIN_LED, HIGH);
#endif
}
void pulse(uint16_t ms) {
#if PIN_LED >= 0
  digitalWrite(PIN_LED, LOW);
  ledOn = true;
  ledOffAt = millis() + ms;
#else
  (void)ms;
#endif
}
void update(uint32_t now) {
#if PIN_LED >= 0
  if (ledOn && (int32_t)(now - ledOffAt) >= 0) { digitalWrite(PIN_LED, HIGH); ledOn = false; }
#else
  (void)now;
#endif
}
}  // namespace led

// ---------------- Baterai ----------------
static float vbat = 0;
static uint32_t lastRead = 0;
static const uint16_t MV[]  = {3300, 3500, 3600, 3650, 3700, 3750, 3800, 3900, 4000, 4100, 4200};
static const uint8_t  PCT[] = {   0,    5,   12,   20,   30,   40,   50,   65,   80,   90,  100};

namespace battery {
void begin() {
#if PIN_BATT >= 0
  analogReadResolution(12);
  analogSetPinAttenuation(PIN_BATT, ADC_11db);
  vbat = analogReadMilliVolts(PIN_BATT) * BATT_DIVIDER / 1000.0f;
#endif
}
void update(uint32_t now) {
#if PIN_BATT >= 0
  if (now - lastRead < 1000) return;
  lastRead = now;
  float v = analogReadMilliVolts(PIN_BATT) * BATT_DIVIDER / 1000.0f;
  vbat = vbat < 0.1f ? v : vbat + (v - vbat) * 0.2f;
#else
  (void)now;
#endif
}
float volts() { return vbat; }
int percent() {
  if (PIN_BATT < 0 || vbat < 2.5f) return -1;
  float mv = vbat * 1000;
  if (mv <= MV[0]) return 0;
  for (int i = 1; i < 11; i++)
    if (mv <= MV[i]) return PCT[i - 1] + (int)((mv - MV[i - 1]) / (MV[i] - MV[i - 1]) * (PCT[i] - PCT[i - 1]));
  return 100;
}
}  // namespace battery
