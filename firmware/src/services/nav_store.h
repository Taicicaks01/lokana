#pragma once
#include <Arduino.h>

// Navigasi dari HP (NAV, v0.6). Data terbaru disimpan di RAM dan dibaca modul Navigasi tiap gambar.
// Pembaruan jarak yang sering TIDAK menjadi event (event membangunkan layar & mereset batas waktu);
// hanya perubahan penting yang dikembalikan update() untuk dikirim sebagai EV_NAV.
struct NavInfo {
  bool active = false;
  uint32_t distM = 0xFFFFFFFF;   // jarak ke belokan berikutnya, 0xFFFFFFFF = tidak diketahui
  char distText[16] = {0};       // teks jarak dari Maps, contoh "200 m"
  char instr[64] = {0};          // contoh "Belok kanan"
  char street[64] = {0};         // contoh "Jl. Udayana"
  uint16_t etaMin = 0xFFFF;      // sisa menit ke tujuan, 0xFFFF = tidak diketahui
  char etaText[16] = {0};        // field akhir opsional, contoh "Tiba 01.02"
  uint8_t iconW = 0, iconH = 0;  // ikon panah 1-bit, maks 32x32 (0 = tanpa ikon)
  uint8_t icon[128] = {0};       // baris demi baris, MSB = kiri, ceil(w/8) byte per baris
  uint32_t at = 0;               // millis pembaruan terakhir
  uint32_t changedAt = 0;        // millis instruksi / ikon terakhir berubah (teks berjalan mulai lagi)
};

namespace navstore {
constexpr uint32_t NEAR_M = 300;           // < 300 m ke belokan: layar menyala & tetap menyala
constexpr uint32_t STALE_MS = 180000;      // 3 menit tanpa pembaruan: navigasi dianggap berhenti
enum Change : uint8_t { NV_NONE = 0, NV_START = 1, NV_TURN = 2, NV_NEAR = 3 };

const NavInfo& get();
uint8_t update(const NavInfo& in);   // hasil: Change (NV_NONE = tidak perlu event)
bool stop();                         // true jika sebelumnya aktif
bool tick(uint32_t now);             // true sekali saat data kedaluwarsa (lalu tidak aktif)
bool near();                         // aktif dan jarak diketahui <= NEAR_M
}
