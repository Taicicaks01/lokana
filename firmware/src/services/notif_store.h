#pragma once
#include <Arduino.h>

// Notifikasi HP (NOTIF) dan panggilan masuk (CALL). Hanya di RAM, tidak pernah ke flash
// (privasi). Diisi layanan link, dibaca modul Notif & layar Panggilan.
struct Notif {
  uint32_t id = 0;
  uint8_t category = 0;       // 0 umum, 1 pesan, 2 email, 3 sosmed, 4 kalender, 5 tak terjawab, 6 sistem
  uint8_t flags = 0;          // bit0 tanpa bunyi, bit1 penting
  uint32_t at = 0;            // millis() saat diterima / diperbarui
  char app[25] = {0};
  char title[49] = {0};
  char body[161] = {0};
  bool silent() const { return flags & 1; }
  bool important() const { return flags & 2; }
};

namespace notifstore {
constexpr uint8_t MAX = 8;
bool upsert(const Notif& n);        // true = notifikasi baru, false = pembaruan id yang sudah ada
bool remove(uint32_t id);
void removeAt(uint8_t i);
void clear();
uint8_t count();
const Notif& at(uint8_t i);         // 0 = terbaru

// Panggilan masuk
void setCall(bool ringing, const char* caller);
bool callRinging();
const char* caller();
}
