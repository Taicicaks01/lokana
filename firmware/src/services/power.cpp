#include "power.h"
#include "config.h"
#include "ota.h"
#include "core/core.h"
#include "drivers/buzzer.h"
#include "drivers/display.h"
#include "drivers/hw.h"
#include <esp_sleep.h>

// Layar "Baterai habis", lalu deep sleep. Bangun lewat sensor sentuh (GPIO RTC 0-5).
// Setelah bangun firmware boot ulang; bootCheck() memeriksa sel lagi.
static void shutdown(const char* why) {
  Serial.printf("[daya] %s: %.2f V -> deep sleep (sentuh untuk menyalakan)\r\n", why, battery::volts());
  Serial.flush();
  if (display::present()) {
    display::power(true);
    display::clear();
    Adafruit_GFX& g = display::gfx();
    g.setTextColor(1);
#if SCREEN_H >= 64
    const int w = 44, h = 22, y = 6, ty = 36;
#else
    const int w = 30, h = 14, y = 1, ty = 20;
#endif
    const int x = (SCREEN_W - w - 4) / 2;
    g.drawRect(x, y, w, h, 1);
    g.drawRect(x + 1, y + 1, w - 2, h - 2, 1);
    g.fillRect(x + w, y + h / 2 - 3, 4, 6, 1);   // kutub
    g.fillRect(x + 4, y + 4, 3, h - 8, 1);       // sisa sedikit
    display::centerText("Baterai habis", ty);
#if SCREEN_H >= 64
    display::centerText("Isi daya dulu", ty + 12);
#endif
    display::show();
  }
  buzzer::play(MEL_SLEEP);
  uint32_t t = millis();
  while (millis() - t < 2500) { buzzer::update(millis()); delay(10); }
  buzzer::stop();
  // Jangan tidur selagi sensor masih disentuh (langsung bangun lagi)
  t = millis();
  while (digitalRead(PIN_BTN) == (BTN_ACTIVE_LOW ? LOW : HIGH) && millis() - t < 5000) delay(10);
  display::power(false);
  esp_deep_sleep_enable_gpio_wakeup(1ULL << PIN_BTN,
                                    BTN_ACTIVE_LOW ? ESP_GPIO_WAKEUP_GPIO_LOW : ESP_GPIO_WAKEUP_GPIO_HIGH);
  esp_deep_sleep_start();
}

namespace power {

static bool inited = false, wasLow = false, wasChg = false;
static uint32_t lowAt = 0;

void bootCheck(bool oled) {
  (void)oled;
#if PIN_BATT >= 0
  float v = battery::volts();
  Serial.printf("[daya] baterai %.2f V (%d%%), charger %s, pembagi %.3f%s\r\n", v, battery::percent(),
                battery::charging() ? "dicolok" : "tidak", battery::divider(), battery::calibrated() ? " (kalibrasi)" : "");
  // Histeresis 0.05 V: sel yang baru pulih sedikit setelah tidur belum dianggap cukup
  if (v > 0 && v < BATT_CUTOFF_V + 0.05f && !battery::externalPower()) shutdown("baterai kritis saat menyala");
#endif
}

void update(uint32_t now) {
#if PIN_BATT >= 0 || PIN_CHG >= 0
  bool chg = battery::charging(), low = battery::low();
  if (!inited) { inited = true; wasChg = chg; wasLow = low; lowAt = now; return; }

  if (chg != wasChg) {
    wasChg = chg;
    Serial.printf("[daya] charger %s\r\n", chg ? "dicolok" : "dicabut");
    if (chg) {
      core::wake();
      core::toast("Mengisi daya", 1500);
      buzzer::play(MEL_ROLL_DONE);
    }
  }

  // Peringatan saat baru lemah (layar dinyalakan), lalu diulang tiap 10 menit hanya jika layar menyala
  if (low && (!wasLow || (core::screenOn() && (int32_t)(now - lowAt) > 600000))) {
    if (!wasLow) {
      Serial.printf("[daya] baterai lemah: %.2f V (%d%%)\r\n", battery::volts(), battery::percent());
      core::wake();
    }
    lowAt = now;
    core::toast("Baterai lemah", 2500);
    buzzer::play(MEL_LOSE);
  }
  wasLow = low;

  if (battery::critical() && !ota::active()) shutdown("baterai kritis");
#else
  (void)now;
#endif
}

}  // namespace power
