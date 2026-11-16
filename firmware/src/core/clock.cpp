#include "clock.h"
#include "config.h"
#include "core/settings.h"
#include <WiFi.h>
#include <sys/time.h>

enum State : uint8_t { ST_IDLE, ST_CONNECTING, ST_NTP, ST_OK, ST_FAIL, ST_MANUAL, ST_BUILD, ST_LINKED };
static State state = ST_IDLE;
static uint32_t since = 0;

static void setState(State s) { state = s; since = millis(); }

// String TZ POSIX dari selisih menit. Tanda POSIX terbalik: UTC+8 -> "LKT-8:00"
static char tzStr[16];
static void applyTz(int16_t min) {
  int m = -min;
  snprintf(tzStr, sizeof(tzStr), "LKT%c%d:%02d", m < 0 ? '-' : '+', abs(m) / 60, abs(m) % 60);
  setenv("TZ", tzStr, 1);
  tzset();
}
static void wifiOff() { WiFi.disconnect(true); WiFi.mode(WIFI_OFF); }

static void fromBuildTime() {
  static const char M[] = "JanFebMarAprMayJunJulAugSepOctNovDec";
  char mon[4] = {0};
  int d, y, hh, mm, ss;
  if (sscanf(__DATE__, "%3s %d %d", mon, &d, &y) != 3 || sscanf(__TIME__, "%d:%d:%d", &hh, &mm, &ss) != 3) return;
  const char* p = strstr(M, mon);
  if (!p) return;
  struct tm t = {};
  t.tm_year = y - 1900; t.tm_mon = (p - M) / 3; t.tm_mday = d;
  t.tm_hour = hh; t.tm_min = mm; t.tm_sec = ss;
  clockx::setEpoch(mktime(&t));
  setState(ST_BUILD);
}

namespace clockx {

void begin() {
  applyTz(settings::get().tzMin);
  if (strlen(WIFI_SSID) > 0) {
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASS);
    setState(ST_CONNECTING);
    Serial.printf("[jam] menghubungkan WiFi \"%s\"...\r\n", WIFI_SSID);
  }
}

void update(uint32_t now) {
  if (state == ST_CONNECTING) {
    if (WiFi.status() == WL_CONNECTED) {
      configTzTime(tzStr, NTP_SERVER1, NTP_SERVER2);
      setState(ST_NTP);
    } else if (now - since > 15000) {
      Serial.println("[jam] WiFi gagal");
      wifiOff();
      setState(ST_FAIL);
#ifdef WOKWI_SIM
      if (!valid()) fromBuildTime();
#endif
    }
  } else if (state == ST_NTP) {
    if (valid()) {
      Serial.println("[jam] NTP ok, WiFi dimatikan");
      wifiOff();
      setState(ST_OK);
    } else if (now - since > 20000) {
      Serial.println("[jam] NTP timeout");
      wifiOff();
      setState(ST_FAIL);
#ifdef WOKWI_SIM
      if (!valid()) fromBuildTime();
#endif
    }
  }
}

bool valid() { return time(nullptr) > 1700000000; }

bool get(struct tm& t) {
  time_t n = time(nullptr);
  localtime_r(&n, &t);
  return valid();
}

void setEpoch(time_t epoch) {
  struct timeval tv = {epoch, 0};
  settimeofday(&tv, nullptr);
  setState(ST_LINKED);
}

void setTzOffset(int16_t minutes) {
  minutes = constrain(minutes, -720, 840);
  if (minutes == settings::get().tzMin) { applyTz(minutes); return; }
  settings::get().tzMin = minutes;
  settings::save();
  applyTz(minutes);
}

int16_t tzOffset() { return settings::get().tzMin; }

void setManual(int h, int m) {
  struct tm t;
  if (!get(t)) { memset(&t, 0, sizeof(t)); t.tm_year = 126; t.tm_mday = 1; }
  t.tm_hour = constrain(h, 0, 23); t.tm_min = constrain(m, 0, 59); t.tm_sec = 0;
  setEpoch(mktime(&t));
  setState(ST_MANUAL);
}

const char* status() {
  switch (state) {
    case ST_CONNECTING: return "WiFi...";
    case ST_NTP:        return "NTP...";
    case ST_OK:         return "NTP";
    case ST_MANUAL:     return "manual";
    case ST_BUILD:      return "jam build";
    case ST_LINKED:     return "sinkron";
    case ST_FAIL:       return valid() ? "offline" : "belum diatur";
    default:         return valid() ? "RTC" : "belum diatur";
  }
}

}  // namespace clockx
