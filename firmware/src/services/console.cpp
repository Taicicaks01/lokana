#include "console.h"
#include "config.h"
#include "core/core.h"
#include "core/face.h"
#include "core/clock.h"
#include "core/settings.h"
#include "drivers/display.h"
#include "drivers/hw.h"
#include "services/link.h"
#include "services/text_store.h"
#include <Wire.h>

static char buf[128];
static uint8_t len = 0;

static void help() {
  Serial.print(
    "\r\n=== Perintah " LOKANA_OS " ===\r\n"
    "help                 daftar perintah\r\n"
    "list                 daftar modul\r\n"
    "go <modul>           buka modul (contoh: go dadu)\r\n"
    "expr <nama>          ekspresi Lokana (tanpa nama = daftar)\r\n"
    "roll                 lempar dadu\r\n"
    "text <isi>           tampilkan teks di modul Teks\r\n"
    "find [detik|stop]    bunyikan cari kunci (default 10 dtk)\r\n"
    "ble                  status BLE & pairing\r\n"
    "forget               hapus semua pairing HP\r\n"
    "time HH:MM           atur jam manual\r\n"
    "tap|double|triple|long   simulasi tombol\r\n"
    "info                 status perangkat\r\n"
    "scan                 pindai perangkat I2C\r\n"
    "i2c <kHz>            ganti kecepatan I2C (contoh: i2c 100)\r\n"
    "oled                 pulihkan bus I2C & inisialisasi ulang OLED\r\n"
    "reset                pengaturan default\r\n");
}

static void handle(char* line) {
  while (*line == ' ') line++;
  if (!*line) return;
  char* arg = strchr(line, ' ');
  if (arg) { *arg++ = 0; while (*arg == ' ') arg++; } else arg = (char*)"";

  if (!strcasecmp(line, "help") || !strcmp(line, "?")) help();
  else if (!strcasecmp(line, "list")) {
    for (uint8_t i = 0; i < core::moduleCount(); i++)
      Serial.printf("  %d. %s%s\r\n", i + 1, core::moduleAt(i)->name(), core::moduleAt(i)->hidden() ? " (sistem)" : "");
  } else if (!strcasecmp(line, "go")) {
    if (!events::post(EV_GOTO, 0, arg)) Serial.println("antrian penuh");
  } else if (!strcasecmp(line, "expr")) {
    Expression e;
    if (*arg && expressionFromName(arg, e)) { events::post(EV_EXPRESSION, e); Serial.printf("ok: %s\r\n", expressionName(e)); }
    else {
      Serial.print("ekspresi: ");
      for (uint8_t i = 0; i < EXP_COUNT; i++) { Serial.print(expressionName((Expression)i)); Serial.print(' '); }
      Serial.println();
    }
  } else if (!strcasecmp(line, "roll")) events::post(EV_ROLL);
  else if (!strcasecmp(line, "text")) {
    TextMsg m;
    strlcpy(m.text, arg, sizeof(m.text));
    for (char* c = m.text; *c; c++) if (*c == '|') *c = '\n';   // '|' = baris baru
    textstore::setCurrent(m);
    events::post(EV_TEXT);
  } else if (!strcasecmp(line, "find")) {
    events::post(EV_FIND_KEYS, !strcasecmp(arg, "stop") ? 0 : (atoi(arg) > 0 ? atoi(arg) : 10));
  } else if (!strcasecmp(line, "ble")) lklink::printStatus();
  else if (!strcasecmp(line, "forget")) lklink::forgetBonds();
  else if (!strcasecmp(line, "time")) {
    int h, m;
    if (sscanf(arg, "%d:%d", &h, &m) == 2) { clockx::setManual(h, m); events::post(EV_GOTO, 0, "Jam"); Serial.println("ok"); }
    else Serial.println("format: time 14:30");
  } else if (!strcasecmp(line, "tap")) core::injectGesture(G_TAP);
  else if (!strcasecmp(line, "double")) core::injectGesture(G_DOUBLE);
  else if (!strcasecmp(line, "triple")) core::injectGesture(G_TRIPLE);
  else if (!strcasecmp(line, "long")) core::injectGesture(G_LONG);
  else if (!strcasecmp(line, "info")) {
    Serial.printf("%s v%s | OLED %s (SDA=%d SCL=%d) | modul: %s | layar %s | baterai %d%% | jam %s | uptime %lus\r\n",
                  LOKANA_OS, FW_VERSION, display::present() ? "ok" : "TIDAK ADA", PIN_SDA, PIN_SCL,
                  core::current() ? core::current()->name() : "-", core::screenOn() ? "nyala" : "mati",
                  battery::percent(), clockx::status(), millis() / 1000);
    lklink::printStatus();
    Serial.printf("  layar %dx%d | loop terlama %lums | kirim frame %luus | I2C %lukHz | pulih otomatis %u kali\r\n",
                  SCREEN_W, SCREEN_H, core::loopMaxMs(), display::lastShowUs(), display::i2cClock() / 1000, display::recoverCount());
  } else if (!strcasecmp(line, "oled")) {
    display::recover();
    uint32_t t = micros(); display::show();
    Serial.printf("  tes kirim frame: %luus\r\n", micros() - t);
  } else if (!strcasecmp(line, "scan")) {
    int n = 0;
    for (uint8_t a = 1; a < 127; a++) {
      Wire.beginTransmission(a);
      if (Wire.endTransmission() == 0) { Serial.printf("  I2C 0x%02X\r\n", a); n++; }
    }
    Serial.printf("  %d perangkat\r\n", n);
  } else if (!strcasecmp(line, "i2c")) {
    int k = atoi(arg);
    if (k >= 10 && k <= 1000) { display::setI2cClock(k * 1000UL); Serial.printf("ok: I2C %dkHz\r\n", k); }
    else Serial.printf("I2C sekarang %lukHz. format: i2c 100\r\n", display::i2cClock() / 1000);
  } else if (!strcasecmp(line, "reset")) {
    settings::reset(); events::post(EV_SETTINGS); Serial.println("ok: pengaturan default");
  } else Serial.printf("perintah tidak dikenal: %s (ketik help)\r\n", line);
}

namespace console {

void begin() {
  Serial.printf("\r\n%s v%s siap. Ketik 'help'.\r\n", LOKANA_OS, FW_VERSION);
}

void feed(char c) {
  if (c == '\r' || c == '\n') {
    if (len) { buf[len] = 0; Serial.printf("> %s\r\n", buf); handle(buf); len = 0; }
  } else if (c == 8 || c == 127) { if (len) len--; }
  else if (len < sizeof(buf) - 1) buf[len++] = c;
}

}  // namespace console
