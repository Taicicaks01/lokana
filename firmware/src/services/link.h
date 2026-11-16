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

// Pesan D->H tanpa diminta: hanya ke host yang sudah HELLO (lihat spesifikasi §3).
// Modul boleh memanggil ini; modul tidak membaca BLE/USB langsung.
void reportDice(uint8_t dice, const uint8_t* values, uint8_t count);
void reportButton(uint8_t gesture, const char* module);   // 1 tap, 2 double, 3 triple, 4 tahan
void reportSettings();            // pengaturan diubah dari menu Lokana
bool findPhone(bool ring);        // false jika tidak ada HP (BLE) yang sudah HELLO
bool phoneReady();                // ada HP tersambung yang sudah HELLO
void reportFindKeys(bool on, uint8_t seconds);   // bunyi cari kunci mulai / berhenti
void consoleActivity();           // ada perintah console di USB -> berhenti kirim frame tanpa diminta

void rename(const char* utf8);    // ganti nama Bluetooth ("" = bawaan): simpan + iklan ulang
const char* deviceName();         // nama yang berlaku (UTF-8) = nama iklan BLE, bawaan BLE_NAME_DEFAULT
void displayName(char* out, size_t cap);   // nama untuk OLED (ASCII, Dewanagari -> Latin)
const char* bleStatus();          // "mati", "iklan", "pairing", "tersambung"
uint8_t bondCount();
void forgetBonds();               // hapus semua pairing (menu "Lupakan HP" / console forget)
void printStatus();               // ringkasan ke Serial (console "ble")

}
