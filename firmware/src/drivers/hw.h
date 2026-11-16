#pragma once
#include <Arduino.h>

// LED bawaan & baterai (opsional)
namespace led {
void begin();
void pulse(uint16_t ms);
void update(uint32_t now);
}

namespace battery {
void begin();
void update(uint32_t now);
float volts();
int percent();     // -1 = tidak ada sensor / USB
}
