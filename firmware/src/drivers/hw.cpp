#include "hw.h"
#include "config.h"
#include <Preferences.h>

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
// Pembagi R1/R2 dari sisi saklar (sebelum D1) ke GPIO1. Tanpa sel (saklar OFF + USB) GPIO1 hanya
// ±0.3 V (bocor D1) -> dianggap tidak terbaca. Deteksi charge: IN+ TP4056 -> 100k -> GPIO4 -> 100k -> GND.
static float vbat = 0, div_ = BATT_DIVIDER;
static bool cal = false, chg = false, lowF = false;
static uint8_t critN = 0;
static uint32_t lastRead = 0;
// Kurva sel LiPo (beban ringan). 3.40 V = 0% (batas deep sleep firmware).
static const uint16_t MV[]  = {3400, 3500, 3600, 3650, 3700, 3750, 3800, 3900, 4000, 4100, 4200};
static const uint8_t  PCT[] = {   0,    5,   12,   20,   30,   40,   50,   65,   80,   90,  100};

static uint16_t avgMv(int pin, int n) {
  if (pin < 0) return 0;
  uint32_t a = 0;
  for (int i = 0; i < n; i++) a += analogReadMilliVolts(pin);
  return a / n;
}

static bool usbHost() {
#if ARDUINO_USB_CDC_ON_BOOT && ARDUINO_USB_MODE
  return HWCDC::isPlugged();
#else
  return false;
#endif
}

namespace usb {
bool host() { return usbHost(); }
}

static void readChg() {
#if PIN_CHG >= 0
  uint16_t mv = avgMv(PIN_CHG, 4);
  if (mv > 2000) chg = true;                      // ±2.5 V saat charger dicolok
  else if (mv < 1500) chg = false;                // di antaranya: pertahankan (histeresis)
#endif
}

static void readBatt(bool first) {
#if PIN_BATT >= 0
  float v = avgMv(PIN_BATT, 16) * div_ / 1000.0f;
  if (v < 2.5f) { vbat = 0; return; }             // tidak ada sel di jalur (saklar OFF)
  vbat = (first || vbat < 0.1f) ? v : vbat + (v - vbat) * 0.2f;
#else
  (void)first;
#endif
}

namespace battery {
void begin() {
#if PIN_BATT >= 0 || PIN_CHG >= 0
  analogReadResolution(12);
#endif
#if PIN_BATT >= 0
  analogSetPinAttenuation(PIN_BATT, ADC_11db);
  Preferences p;
  if (p.begin("batt", true)) {
    float d = p.getFloat("div", 0);
    p.end();
    if (d >= 1.6f && d <= 2.6f) { div_ = d; cal = true; }
  }
#endif
#if PIN_CHG >= 0
  analogSetPinAttenuation(PIN_CHG, ADC_11db);
#endif
  readChg();
  readBatt(true);
  lowF = vbat > 0 && vbat < BATT_WARN_V;
}

void update(uint32_t now) {
#if PIN_BATT >= 0 || PIN_CHG >= 0
  if ((int32_t)(now - lastRead) < 1000) return;
  lastRead = now;
  readChg();
  readBatt(false);
  if (vbat <= 0 || chg) lowF = false;
  else if (vbat < BATT_WARN_V) lowF = true;
  else if (vbat > BATT_WARN_V + 0.10f) lowF = false;
  if (vbat > 0 && vbat < BATT_CUTOFF_V && !chg && !usbHost()) { if (critN < 255) critN++; }
  else critN = 0;
#else
  (void)now;
#endif
}

float volts() { return vbat; }
uint16_t millivolts() { return vbat > 0 ? (uint16_t)(vbat * 1000 + 0.5f) : 0; }
int percent() {
  if (PIN_BATT < 0 || vbat < 2.5f) return -1;
  float mv = vbat * 1000;
  if (mv <= MV[0]) return 0;
  for (int i = 1; i < 11; i++)
    if (mv <= MV[i]) return PCT[i - 1] + (int)((mv - MV[i - 1]) / (MV[i] - MV[i - 1]) * (PCT[i] - PCT[i - 1]));
  return 100;
}
bool charging() { return chg; }
bool low() { return lowF; }
bool critical() { return critN >= 10; }
bool externalPower() { return chg || usbHost() || percent() < 0; }
float divider() { return div_; }
bool calibrated() { return cal; }

bool calibrate(float realV) {
#if PIN_BATT >= 0
  uint16_t mv = avgMv(PIN_BATT, 64);
  if (mv < 1000 || realV < 3.0f || realV > 4.5f) return false;
  float d = realV * 1000.0f / mv;
  if (d < 1.6f || d > 2.6f) return false;
  Preferences p;
  p.begin("batt", false);
  p.putFloat("div", d);
  p.end();
  div_ = d; cal = true;
  readBatt(true);
  return true;
#else
  (void)realV;
  return false;
#endif
}

void resetCalibration() {
  Preferences p;
  p.begin("batt", false);
  p.remove("div");
  p.end();
  div_ = BATT_DIVIDER; cal = false;
  readBatt(true);
}

uint16_t pinMv() { return avgMv(PIN_BATT, 16); }
uint16_t chgMv() { return avgMv(PIN_CHG, 16); }
}  // namespace battery
