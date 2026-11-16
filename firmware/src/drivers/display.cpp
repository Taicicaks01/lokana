#include "display.h"
#include "config.h"
#include <Wire.h>

// Subclass kecil supaya kecepatan I2C bisa diubah saat berjalan
class Oled : public Adafruit_SSD1306 {
public:
  using Adafruit_SSD1306::Adafruit_SSD1306;
  void setClock(uint32_t hz) { wireClk = restoreClk = hz; }
};

static Oled oled(SCREEN_W, PANEL_H, &Wire, -1, I2C_HZ, I2C_HZ);
static bool ok = false;
static uint32_t showUs = 0, clk = I2C_HZ;
static uint8_t slowFrames = 0;
static uint16_t recovers = 0;

static bool ack() {
  Wire.beginTransmission(OLED_ADDR);
  return Wire.endTransmission() == 0;
}

// 9 pulsa SCL + STOP: membebaskan slave yang menahan SDA
static void busClear() {
  Wire.end();
  pinMode(PIN_SDA, INPUT_PULLUP);
  pinMode(PIN_SCL, OUTPUT_OPEN_DRAIN);
  digitalWrite(PIN_SCL, HIGH);
  delayMicroseconds(10);
  for (int i = 0; i < 9 && digitalRead(PIN_SDA) == LOW; i++) {
    digitalWrite(PIN_SCL, LOW);  delayMicroseconds(10);
    digitalWrite(PIN_SCL, HIGH); delayMicroseconds(10);
  }
  pinMode(PIN_SDA, OUTPUT_OPEN_DRAIN);       // STOP: SDA naik saat SCL tinggi
  digitalWrite(PIN_SDA, LOW);  delayMicroseconds(10);
  digitalWrite(PIN_SDA, HIGH); delayMicroseconds(10);
  Wire.begin(PIN_SDA, PIN_SCL, clk);
  Wire.setTimeOut(20);
}

namespace display {

bool begin() {
  Wire.begin(PIN_SDA, PIN_SCL, clk);
  Wire.setTimeOut(20);              // jangan biarkan I2C macet lama
  Wire.beginTransmission(OLED_ADDR);
  bool ack = (Wire.endTransmission() == 0);
  ok = oled.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR, true, false) && ack;
  oled.setTextWrap(false);
  oled.clearDisplay();
  oled.display();
  return ok;
}

Adafruit_SSD1306& gfx() { return oled; }
void clear() { oled.clearDisplay(); }
void show() {
  // OLED tidak menjawab: jangan kirim frame (tiap kirim bisa macet ~8 dtk).
  // Coba sambung ulang tiap 3 detik saja.
  static uint32_t lastTry = 0;
  if (!ok) {
    if (millis() - lastTry >= 3000) { lastTry = millis(); if (ack()) recover(); }
    return;
  }
  uint32_t t = micros();
  oled.display();
  showUs = micros() - t;
  // Frame normal < 30 ms. Kalau berkali-kali sangat lambat, bus I2C kemungkinan macet.
  if (showUs > 200000UL) {
    if (++slowFrames >= 2) { slowFrames = 0; recovers++; recover(); }
  } else slowFrames = 0;
}
bool present() { return ok; }
uint16_t recoverCount() { return recovers; }

bool recover() {
  Wire.end();
  pinMode(PIN_SDA, INPUT_PULLUP);
  pinMode(PIN_SCL, INPUT_PULLUP);
  delayMicroseconds(20);
  Serial.printf("[oled] sebelum pulih: SDA=%s SCL=%s\r\n",
                digitalRead(PIN_SDA) ? "HIGH" : "LOW(macet)", digitalRead(PIN_SCL) ? "HIGH" : "LOW(macet)");
  busClear();
  bool a = ack();
  if (a) {
    oled.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR, false, false);
    oled.setTextWrap(false);
  }
  ok = a;
  Serial.printf("[oled] setelah pulih: %s\r\n", a ? "OLED menjawab" : "OLED TIDAK menjawab");
  return a;
}
uint32_t lastShowUs() { return showUs; }
uint32_t i2cClock() { return clk; }
void setI2cClock(uint32_t hz) { clk = hz; oled.setClock(hz); Wire.setClock(hz); }

void power(bool on) { oled.ssd1306_command(on ? SSD1306_DISPLAYON : SSD1306_DISPLAYOFF); }

void setBrightness(uint8_t level) {
  static const uint8_t C[3] = {0x05, 0x60, 0xFF};
  oled.ssd1306_command(SSD1306_SETCONTRAST);
  oled.ssd1306_command(C[level > 2 ? 2 : level]);
}

void setFlip(bool flip) { oled.setRotation(flip ? 2 : 0); }

uint16_t snapshot(uint8_t* out) {
  const uint16_t bw = (SCREEN_W + 7) / 8;
  memset(out, 0, bw * SCREEN_H);
  for (int y = 0; y < SCREEN_H; y++)
    for (int x = 0; x < SCREEN_W; x++)
      if (oled.getPixel(x, y)) out[y * bw + (x >> 3)] |= 0x80 >> (x & 7);
  return bw * SCREEN_H;
}

int textWidth(const char* s, uint8_t size) { return (int)strlen(s) * 6 * size; }

void centerText(const char* s, int y, uint8_t size) {
  oled.setTextSize(size);
  int x = (SCREEN_W - textWidth(s, size)) / 2;
  oled.setCursor(x < 0 ? 0 : x, y);
  oled.print(s);
}

}  // namespace display
