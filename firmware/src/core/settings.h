#pragma once
#include <Arduino.h>
#include "config.h"

struct Settings {
  uint8_t brightness = 1;     // 0 redup, 1 sedang, 2 terang
  bool    sound      = true;
  uint8_t screenIdx  = 2;     // indeks SCREEN_TIMEOUT_MS
  bool    flip       = false;
  int16_t tzMin      = TZ_OFFSET_MIN;   // selisih zona waktu (menit), dari TIME_SYNC
};

constexpr uint8_t SCREEN_TIMEOUT_COUNT = 5;
extern const uint32_t SCREEN_TIMEOUT_MS[SCREEN_TIMEOUT_COUNT];
extern const char* const SCREEN_TIMEOUT_LABEL[SCREEN_TIMEOUT_COUNT];
extern const char* const BRIGHTNESS_LABEL[3];

namespace settings {
Settings& get();
void load();
void save();
void reset();
uint32_t screenTimeoutMs();   // 0 = tidak pernah
}
