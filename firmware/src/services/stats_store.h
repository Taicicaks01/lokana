#pragma once
#include <Arduino.h>

// Metrik dari PC (PC_STATS, v0.7). Host menentukan metrik apa yang dikirim; device hanya menampilkan.
// Data terbaru di RAM, dibaca modul Monitor tiap gambar. Event hanya saat mulai/berhenti (EV_STATS).
struct Metric {
  uint8_t kind = 0;          // 0 angka, 1 persen (bar), 2 suhu (bar 0-100), lainnya = angka
  char label[11] = {0};      // maks 10 karakter (0.8; dulu 6)
  int32_t v10 = 0;           // nilai x 10 (untuk bar, dan nilai kalau text kosong)
  char unit[5] = {0};        // maks 4 karakter
  char text[12] = {0};       // teks nilai siap tampil dari host (0.8), kosong = device memformat sendiri
};

// Satu baris tampilan: metrik a, dan metrik b di sebelahnya (NONE = satu metrik)
struct StatRow {
  static const uint8_t NONE = 255;
  uint8_t a = 0, b = NONE;
};

namespace statsstore {
constexpr uint8_t MAX = 12;
constexpr uint32_t STALE_MS = 10000;   // spesifikasi: 10 dtk tanpa data = PC terputus

uint8_t count();
const Metric& get(uint8_t i);
// rows/nrows: susunan baris dari host (0.8); nrows 0 = satu metrik per baris. true jika Monitor baru mulai.
bool update(const Metric* m, uint8_t n, const StatRow* rows = nullptr, uint8_t nrows = 0);
uint8_t rowCount();                       // jumlah baris tampilan
StatRow row(uint8_t i);
bool active();
bool tick(uint32_t now);                   // true sekali saat data kedaluwarsa
}
