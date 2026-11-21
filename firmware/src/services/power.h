#pragma once
#include <Arduino.h>

// Daya baterai: peringatan lemah, pemberitahuan mengisi, dan deep sleep saat sel kritis.
// Manajemen daya lain (light sleep, CPU, interval BLE) belum: menunggu hasil ukur arus (docs/ARCHITECTURE.md §2.5).
namespace power {
void bootCheck(bool oled);    // sel sudah kritis saat menyala: tampilkan pesan lalu tidur lagi
void update(uint32_t now);
}
