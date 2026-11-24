#pragma once
#include <Arduino.h>

// Metrik dari PC (PC_STATS, v0.7). Host menentukan metrik apa yang dikirim; device hanya menampilkan.
// Data terbaru di RAM, dibaca modul Monitor tiap gambar. Event hanya saat mulai/berhenti (EV_STATS).
struct Metric {
  uint8_t kind = 0;          // 0 angka, 1 persen (bar), 2 suhu (bar 0-100), lainnya = angka
  char label[7] = {0};       // maks 6 karakter
  int32_t v10 = 0;           // nilai x 10
  char unit[5] = {0};        // maks 4 karakter
};

namespace statsstore {
constexpr uint8_t MAX = 12;
constexpr uint32_t STALE_MS = 10000;   // spesifikasi: 10 dtk tanpa data = PC terputus

uint8_t count();
const Metric& get(uint8_t i);
bool update(const Metric* m, uint8_t n);   // true jika sebelumnya tidak aktif (Monitor baru mulai)
bool active();
bool tick(uint32_t now);                   // true sekali saat data kedaluwarsa
}
