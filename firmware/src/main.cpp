// ============================================================
//  Lokana OS — firmware Lokana
//  "Lokana — melihat untukmu."
//  ESP32-C3 Super Mini + OLED 0.96" 128x64 (varian 0.91" 128x32)
//  Lisensi: MIT (lihat LICENSE)
// ============================================================
#include <Arduino.h>
#include "config.h"
#include "core/core.h"
#include "core/settings.h"
#include "core/clock.h"
#include "drivers/display.h"
#include "drivers/button.h"
#include "drivers/buzzer.h"
#include "drivers/hw.h"
#include "services/console.h"
#include "services/link.h"
#include "modules/face_module.h"
#include "modules/clock_module.h"
#include "modules/dice_module.h"
#include "modules/text_module.h"
#include "modules/image_module.h"
#include "modules/system_modules.h"

// Daftar modul. Modul pertama = layar utama.
// Menambah fitur: buat modul di src/modules/, lalu daftarkan di sini.
static FaceModule  faceModule;
static ClockModule clockModule;
static DiceModule  diceModule;
static TextModule  textModule;
static ImageModule imageModule;
static PairModule  pairModule;     // sistem (tersembunyi)
static FindModule  findModule;     // sistem (tersembunyi)
static PhoneModule phoneModule;    // sistem (tersembunyi)

static void splash() {
  Adafruit_GFX& g = display::gfx();
  display::clear();
  g.setTextColor(1);
  // Logo: "L" + mata + "kana"  (huruf o diganti mata Lokana). Ukuran huruf s: 3 (64 px) / 2 (32 px)
  const int s = SCREEN_H >= 64 ? 3 : 2;
  const int x0 = (SCREEN_W - (25 * s / 2 + 24 * s)) / 2, y = SCREEN_H >= 64 ? 8 : 6;
  g.setTextSize(s);
  g.setCursor(x0, y); g.print('L');
  g.fillRoundRect(x0 + 13 * s / 2, y + 3 * s / 2, 5 * s, 13 * s / 2, 2 * s, 1);
  g.setCursor(x0 + 25 * s / 2, y); g.print("kana");
  g.setTextSize(1);
#if SCREEN_H >= 64
  display::centerText("melihat untukmu", 40);
  display::centerText(LOKANA_OS " v" FW_VERSION, 54);
#else
  display::centerText(LOKANA_OS " v" FW_VERSION, 24);
#endif
  display::show();
}

static const char* resetReason() {
  switch (esp_reset_reason()) {
    case ESP_RST_POWERON:  return "power-on";
    case ESP_RST_SW:       return "software";
    case ESP_RST_PANIC:    return "PANIC (crash)";
    case ESP_RST_INT_WDT:  return "interrupt watchdog";
    case ESP_RST_TASK_WDT: return "task watchdog";
    case ESP_RST_WDT:      return "watchdog";
    case ESP_RST_BROWNOUT: return "BROWNOUT (tegangan drop)";
    case ESP_RST_EXT:      return "tombol RST";
    case ESP_RST_DEEPSLEEP:return "deep sleep";
    default:               return "lainnya";
  }
}

#define TRACE(msg) do { Serial.print("[boot] " msg "\r\n"); Serial.flush(); } while (0)

void setup() {
  Serial.setRxBufferSize(2048);   // frame Lokana Link s.d. 1200 B datang sekaligus lewat USB
  Serial.begin(115200);
  // Tunggu serial monitor (maks 3 dtk) supaya log boot tidak hilang
  uint32_t w = millis();
  while (!Serial && millis() - w < 3000) delay(10);
  delay(100);
  Serial.printf("\r\n[boot] " LOKANA_OS " v" FW_VERSION " | reset: %s\r\n", resetReason());
  randomSeed(esp_random());

  TRACE("settings");  settings::load();
  TRACE("led");       led::begin();
  TRACE("baterai");   battery::begin();
  TRACE("display");   bool oled = display::begin();
  TRACE("buzzer");    buzzer::begin();
  TRACE("tombol");    button::begin();
  TRACE("jam");       clockx::begin();

  if (oled) Serial.printf("[init] OLED ok di 0x%02X (SDA=GPIO%d, SCL=GPIO%d)\r\n", OLED_ADDR, PIN_SDA, PIN_SCL);
  else Serial.printf("[err] OLED tidak menjawab di 0x%02X (SDA=GPIO%d, SCL=GPIO%d)\r\n", OLED_ADDR, PIN_SDA, PIN_SCL);

  TRACE("splash");
  splash();
  buzzer::play(MEL_BOOT);
  led::pulse(300);
  uint32_t t0 = millis();
  while (millis() - t0 < 1200) { buzzer::update(millis()); led::update(millis()); delay(5); }

  core::addModule(&faceModule);
  core::addModule(&clockModule);
  core::addModule(&diceModule);
  core::addModule(&textModule);
  core::addModule(&imageModule);
  core::addModule(&pairModule);
  core::addModule(&findModule);
  core::addModule(&phoneModule);
  TRACE("core");
  core::begin();
  console::begin();
  TRACE("link");      lklink::begin();
  TRACE("siap. ketik 'help'");
}

void loop() {
  lklink::update(millis());
  core::loop();
}
