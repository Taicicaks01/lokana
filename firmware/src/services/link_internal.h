#pragma once
// Antarmuka internal layanan link (hanya untuk link*.cpp)
#include "link.h"

namespace lklink {
// Satu frame utuh dari transport mana pun -> diproses di sini
void dispatch(Transport t, uint8_t type, uint8_t seq, const uint8_t* p, uint16_t n, bool tooBig);
}

namespace link_usb {
void begin();
void update(uint32_t now);
void write(const uint8_t* frame, uint16_t n);   // frame mentah; envelope + CRC ditambahkan di sini
}

namespace link_ble {
void begin(const char* name);
void update(uint32_t now);
bool write(const uint8_t* frame, uint16_t n);   // false jika tidak ada HP tersambung & terenkripsi
bool connected();
bool secure();                                  // tersambung dan terenkripsi + terautentikasi
bool pairing();                                 // passkey sedang ditampilkan
uint8_t bonds();
void forget();
uint16_t mtu();
}
