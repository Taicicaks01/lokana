#pragma once
#include <Arduino.h>
#include <time.h>

// Sumber waktu: WiFi NTP (jika ada SSID), atur manual, atau (Wokwi) jam build.
// Tahap berikutnya: sinkron dari aplikasi lewat Lokana Link (TIME_SYNC).
namespace clockx {
void begin();
void update(uint32_t now);
bool valid();
bool get(struct tm& t);
void setManual(int h, int m);
void setEpoch(time_t epoch);
void setTzOffset(int16_t minutes);   // contoh WITA = 480; disimpan ke pengaturan
int16_t tzOffset();
const char* status();
}
