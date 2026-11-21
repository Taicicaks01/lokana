#pragma once
// ============================================================
//  Lokana OS — konfigurasi hardware & fitur
//  Semua pin bisa ditimpa dari build_flags di platformio.ini
// ============================================================

#define LOKANA_NAME "Lokana"
#define LOKANA_OS "Lokana OS"

// Nama Bluetooth bawaan (UTF-8, maks 26 byte). Bisa diganti dari aplikasi
// (Pengaturan). "locana" = mata (Sansekerta). Di OLED tampil sebagai
// "Lokana_locana-01".
#ifndef BLE_NAME_DEFAULT
#define BLE_NAME_DEFAULT                                                       \
  "Lokana_\xE0\xA4\xB2\xE0\xA5\x8B\xE0\xA4\x9A\xE0\xA4\xA8-01" // Lokana_लोचन-01
#endif
#ifndef FW_VERSION // bisa ditimpa build_flags (env uji OTA)
#define FW_VERSION "0.5.6"
#endif

// ---------- Layar ----------
#define SCREEN_W 128
#ifndef SCREEN_H
#define SCREEN_H 64 // ukuran logis yang dipakai semua modul (varian 0.91": 32)
#endif
#ifndef PANEL_H
#define PANEL_H                                                                \
  SCREEN_H // tinggi panel fisik; boleh > SCREEN_H (hanya baris atas dipakai)
#endif
#define OLED_ADDR 0x3C
#ifndef I2C_HZ
#define I2C_HZ                                                                 \
  400000UL // turunkan ke 100000 jika kabel panjang / OLED tidak stabil
#endif

// ---------- Pin (default: ESP32-C3 Super Mini) ----------
#ifndef PIN_SDA
#define PIN_SDA 9
#endif
#ifndef PIN_SCL
#define PIN_SCL 8
#endif
#ifndef PIN_BTN
#define PIN_BTN 3 // sensor sentuh TTP223 (GPIO9/BOOT dipakai SDA)
#endif
#ifndef BTN_ACTIVE_LOW
#define BTN_ACTIVE_LOW 0 // 1 = tombol ke GND, 0 = TTP223 (aktif HIGH)
#endif
#ifndef PIN_BUZZER
#define PIN_BUZZER 10 // -1 jika tidak ada buzzer
#endif
#ifndef PIN_LED
#define PIN_LED -1 // LED bawaan ada di GPIO8, tapi GPIO8 dipakai SCL
#endif
#ifndef PIN_BATT
#define PIN_BATT -1 // 1 jika pembagi tegangan baterai dipasang
#endif
#ifndef PIN_CHG
#define PIN_CHG -1 // 4 jika deteksi charge (IN+ TP4056 -> 100k -> GPIO4 -> 100k -> GND) dipasang
#endif
// Faktor pembagi bawaan (R1 = R2). Per unit dikalibrasi lewat console `batt cal <volt>` (NVS).
#define BATT_DIVIDER 2.0f
#define BATT_WARN_V 3.55f   // peringatan "Baterai lemah" (ingat drop D1 ±0.3 V ke regulator)
#define BATT_CUTOFF_V 3.40f // di bawah ini selama 10 dtk -> layar mati + deep sleep

// ---------- Waktu & WiFi ----------
#define TZ_OFFSET_MIN 480 // default WITA (UTC+8); diganti TIME_SYNC
#define NTP_SERVER1 "pool.ntp.org"
#define NTP_SERVER2 "time.google.com"
#ifdef WOKWI_SIM
#define WIFI_SSID "Wokwi-GUEST"
#define WIFI_PASS ""
#elif __has_include("secrets.h")
#include "secrets.h"
#else
#define WIFI_SSID ""
#define WIFI_PASS ""
#endif

// ---------- Timing ----------
#define FRAME_MS 30
#define BTN_DEBOUNCE_MS 20
#define BTN_MULTI_MS 300
#define BTN_LONG_MS 650
