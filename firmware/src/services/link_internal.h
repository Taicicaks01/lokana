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
void unpairCurrent();                           // hapus bond HP yang sedang tersambung, lalu putus
void setName(const char* name);                 // ganti nama iklan (UTF-8)
uint16_t mtu();
// Sekali setelah koneksi aman putus: alasan (NimBLE: 0x200 + kode HCI), RSSI terakhir & umurnya (ms).
// RSSI 0 = belum pernah terukur.
bool takeLoss(uint16_t& reason, int8_t& rssi, uint32_t& rssiAgeMs);
}
