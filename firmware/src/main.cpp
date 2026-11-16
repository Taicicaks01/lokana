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
#include "modules/notif_module.h"
#include "modules/system_modules.h"
#include "modules/splash_module.h"
#include "modules/guide_module.h"
#include "modules/left_module.h"

// Daftar modul. Modul pertama = layar utama.
// Menambah fitur: buat modul di src/modules/, lalu daftarkan di sini.
static FaceModule  faceModule;
static ClockModule clockModule;
static NotifModule notifModule;
static DiceModule  diceModule;
static TextModule  textModule;
static ImageModule imageModule;
static PairModule  pairModule;     // sistem (tersembunyi)
static FindModule  findModule;     // sistem (tersembunyi)
static PhoneModule phoneModule;    // Cari HP (modul biasa sejak 0.5.2)
static CallModule  callModule;     // sistem (tersembunyi)

static SplashModule splashModule(faceModule.face());   // splash boot लोचन (tersembunyi)
static GuideModule guideModule;                         // panduan cara pakai (tersembunyi)
static LeftModule leftModule;                           // pengingat HP tertinggal (tersembunyi)

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
  // Tunggu serial monitor (maks 3 dtk) supaya log boot tidak hilang. Hanya kalau USB tersambung ke
  // komputer: dari baterai / charger tidak menunggu, jadi splash langsung tampil.
  uint32_t w = millis();
#if ARDUINO_USB_CDC_ON_BOOT && ARDUINO_USB_MODE
  while (!Serial && HWCDC::isPlugged() && millis() - w < 3000) delay(10);
#else
  while (!Serial && millis() - w < 3000) delay(10);
#endif
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

  led::pulse(300);
  core::addModule(&faceModule);
  core::addModule(&clockModule);
  core::addModule(&notifModule);
  core::addModule(&phoneModule);
  core::addModule(&diceModule);
  core::addModule(&textModule);
  core::addModule(&imageModule);
  core::addModule(&pairModule);
  core::addModule(&findModule);
  core::addModule(&callModule);
  core::addModule(&splashModule);
  core::addModule(&guideModule);
  core::addModule(&leftModule);
  TRACE("core");
  core::begin();
  core::goTo(splashModule.name());   // splash berjalan di loop: BLE & console sudah aktif selama animasi
  console::begin();
  TRACE("link");      lklink::begin();
  TRACE("siap. ketik 'help'");
}

void loop() {
  lklink::update(millis());
  core::loop();
}
