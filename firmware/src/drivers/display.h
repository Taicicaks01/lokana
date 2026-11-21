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
// Salin isi layar (koordinat logis, sudah termasuk putar 180°) ke format bitmap Lokana Link:
// baris demi baris, MSB = kiri. out minimal ceil(SCREEN_W/8)*SCREEN_H byte. Hasil: jumlah byte.
uint16_t snapshot(uint8_t* out);

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
// Ikon baterai 15x8 (badan 13x8 + kutub). pct -1 = kosong. charging: isian naik bertahap (animasi).
void batteryIcon(int x, int y, int pct, bool charging, uint32_t now);
}
