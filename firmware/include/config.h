#pragma once
// ============================================================
//  Lokana OS — konfigurasi hardware & fitur
//  Semua pin bisa ditimpa dari build_flags di platformio.ini
// ============================================================

#define LOKANA_NAME "Lokana"
#define LOKANA_OS "Lokana OS"
#define FW_VERSION "0.3.0"

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
#define PIN_SDA 8
#endif
#ifndef PIN_SCL
#define PIN_SCL 9
#endif
#ifndef PIN_BTN
#define PIN_BTN 3 // sensor sentuh TTP223 (GPIO9/BOOT dipakai SCL)
#endif
#ifndef BTN_ACTIVE_LOW
#define BTN_ACTIVE_LOW 0 // 1 = tombol ke GND, 0 = TTP223 (aktif HIGH)
#endif
#ifndef PIN_BUZZER
#define PIN_BUZZER 10 // -1 jika tidak ada buzzer
#endif
#ifndef PIN_LED
#define PIN_LED -1 // LED bawaan ada di GPIO8, tapi GPIO8 dipakai SDA
#endif
#ifndef PIN_BATT
#define PIN_BATT -1 // 1 jika pembagi tegangan baterai dipasang
#endif
#define BATT_DIVIDER 2.0f

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
