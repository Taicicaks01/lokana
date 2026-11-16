#pragma once
#include <Adafruit_SSD1306.h>

// Layar OLED. Semua modul menggambar di area logis SCREEN_W x SCREEN_H (lihat config.h).
namespace display {
bool begin();                       // true jika OLED menjawab di I2C
Adafruit_SSD1306& gfx();
void clear();
void show();
void power(bool on);
void setBrightness(uint8_t level);  // 0 redup, 1 sedang, 2 terang
void setFlip(bool flip);
bool present();

// Diagnostik
uint32_t lastShowUs();              // durasi kirim frame terakhir ke OLED (mikrodetik)
void setI2cClock(uint32_t hz);      // ganti kecepatan I2C saat berjalan
uint32_t i2cClock();
// Pulihkan bus I2C yang macet lalu inisialisasi ulang OLED.
// Melaporkan level SDA/SCL sebelum pemulihan lewat Serial. true jika OLED menjawab lagi.
bool recover();
uint16_t recoverCount();            // berapa kali pemulihan otomatis terjadi

// Helper teks
void centerText(const char* s, int y, uint8_t size = 1);
int textWidth(const char* s, uint8_t size = 1);
}
