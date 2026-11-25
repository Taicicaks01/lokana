#pragma once
#include <Arduino.h>

// Pita frekuensi audio PC (AUDIO_BANDS, v0.8, Mode Meja). Host sudah menghaluskan & menguatkan; device hanya
// menggambar. Data terbaru di RAM, dibaca modul Visualizer tiap gambar. Event hanya saat mulai/berhenti (EV_AUDIO).
namespace audiostore {
constexpr uint8_t MIN = 8, MAX = 32;
constexpr uint32_t STALE_MS = 1500;      // spesifikasi: 1,5 dtk tanpa pesan = selesai

// style: -1 = tidak dikirim. true jika visualizer baru mulai.
bool update(const uint8_t* bands, uint8_t n, int style);
uint8_t count();
const uint8_t* bands();
bool active();
int takeStyle();                         // gaya baru dari host (sekali), -1 = tidak ada
int tick(uint32_t now);                  // 1 = demo baru mulai, -1 = data kedaluwarsa (sekali), 0 = tidak ada
void demo(uint32_t ms, int style);       // console `viz`: pita buatan tanpa PC
}
