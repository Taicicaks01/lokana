#pragma once
#include <Arduino.h>

// Satu tombol (BOOT / TTP223) -> gestur
enum Gesture : uint8_t { G_NONE, G_TAP, G_DOUBLE, G_TRIPLE, G_LONG };

namespace button {
void begin();
Gesture update(uint32_t now);
bool pressed();                 // sedang ditekan (termasuk tekanan singkat yang belum diproses)
uint32_t lastActivity();
const char* name(Gesture g);
}
