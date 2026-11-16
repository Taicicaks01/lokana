#pragma once
#include <Arduino.h>

// ============================================================
//  Layanan Lokana Link: menerima frame dari USB (envelope A5 5A + CRC)
//  dan BLE (aliran byte), menerjemahkannya jadi event untuk modul,
//  dan mengirim balasan ke transport asal.
//  Spesifikasi: protocol/LOKANA_LINK.md
// ============================================================
namespace lklink {

enum Transport : uint8_t { TR_USB, TR_BLE, TR_COUNT };

void begin();                     // panggil setelah Serial & console siap
void update(uint32_t now);        // panggil tiap loop: baca USB + antrean BLE

// Kirim satu frame ke transport tertentu
void send(Transport t, uint8_t type, uint8_t seq, const uint8_t* payload, uint16_t len);

const char* deviceName();         // "Lokana-1A2B"
const char* bleStatus();          // "mati", "iklan", "pairing", "tersambung"
uint8_t bondCount();
void forgetBonds();               // hapus semua pairing (menu "Lupakan HP" / console forget)
void printStatus();               // ringkasan ke Serial (console "ble")

}
