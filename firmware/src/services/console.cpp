#include "console.h"
#include "ota.h"
#include "config.h"
#include "core/core.h"
#include "core/face.h"
#include "core/clock.h"
#include "core/settings.h"
#include "drivers/display.h"
#include "drivers/hw.h"
#include "drivers/buzzer.h"
#include "services/link.h"
#include "services/text_store.h"
#include "services/image_store.h"
#include "core/settings.h"
#include "services/notif_store.h"
#include <Wire.h>
#include <esp_adc_cal.h>

static char buf[128];
static uint8_t len = 0;

static void help() {
  Serial.print(
    "\r\n=== Perintah " LOKANA_OS " ===\r\n"
    "help                 daftar perintah\r\n"
    "list                 daftar modul\r\n"
    "go <modul>           buka modul (contoh: go dadu)\r\n"
    "expr <nama>          ekspresi Lokana (tanpa nama = daftar)\r\n"
    "roll [jenis]         lempar dadu (1d6 2d6 d4 d8 d10 d12 d20 koin)\r\n"
    "text <isi>           tampilkan teks di modul Teks\r\n"
    "find [detik|stop]    bunyikan cari kunci (default 10 dtk)\r\n"
    "phone                cari HP (bunyikan HP yang tersambung)\r\n"
    "notif app|judul|isi  notifikasi uji ('notif clear' = hapus semua)\r\n"
    "call <nama>|stop     panggilan masuk uji\r\n"
    "img                  tampilkan animasi uji di modul Gambar\r\n"
    "splash [ms]          putar ulang splash boot (ms = bekukan di waktu itu)\r\n"
    "guide [ms]           putar Panduan cara pakai (ms = bekukan di waktu itu)\r\n"
    "left [0]             uji pengingat HP tertinggal (0 = HP kembali)\r\n"
    "name [nama]          nama Bluetooth (kosong = bawaan)\r\n"
    "ble                  status BLE & pairing\r\n"
    "ota                  status slot firmware & masa uji OTA\r\n"
    "tone <Hz> [ms]       bunyikan satu nada (bawaan 500 ms)\r\n"
    "sweep [a] [b] [s] [ms]  sapuan nada a..b Hz langkah s (bawaan 1500 5000 100 400)\r\n"
    "adc                  tegangan mentah GPIO1 (baterai) & GPIO4 (charge)\r\n"
    "btnraw [dtk]         rekam level mentah pin tombol + lamanya (bawaan 10 dtk)\r\n"
    "batt [cal <V>|cal reset]  status baterai; kalibrasi pembagi dari volt multimeter\r\n"
    "forget               hapus semua pairing HP\r\n"
    "time HH:MM           atur jam manual\r\n"
    "tap|double|triple|long   simulasi tombol\r\n"
    "info                 status perangkat\r\n"
    "scan                 pindai perangkat I2C\r\n"
    "i2c <kHz>            ganti kecepatan I2C (contoh: i2c 100)\r\n"
    "oled                 pulihkan bus I2C & inisialisasi ulang OLED\r\n"
    "reset                pengaturan default\r\n");
}

// Sapuan nada untuk mencari frekuensi resonansi buzzer (paling nyaring). Sengaja blocking (alat bring-up):
// OLED menampilkan frekuensi yang sedang berbunyi supaya bisa dibaca sambil mendengarkan.
static void sweep(const char* arg) {
  int a = 1500, b = 5000, step = 100, ms = 400;
  sscanf(arg, "%d %d %d %d", &a, &b, &step, &ms);
  a = constrain(a, 100, 12000); b = constrain(b, a, 12000);
  step = constrain(step, 10, 2000); ms = constrain(ms, 100, 3000);
  int n = (b - a) / step + 1;
  Serial.printf("sapuan %d..%d Hz, langkah %d, %d ms per nada (%d nada)\r\n", a, b, step, ms, n);
  Adafruit_GFX& g = display::gfx();
  for (int i = 0; i < n; i++) {
    int f = a + i * step;
    display::clear();
    g.setTextColor(1);
    char t[16];
    snprintf(t, sizeof(t), "%d Hz", f);
    display::centerText(t, SCREEN_H >= 64 ? 18 : 6, 2);
    snprintf(t, sizeof(t), "nada %d/%d", i + 1, n);
    display::centerText(t, SCREEN_H >= 64 ? 44 : 24);
    display::show();
    Serial.printf("  %d Hz\r\n", f);
    buzzer::raw(f);
    delay(ms);
    buzzer::raw(0);
    delay(120);
  }
  buzzer::raw(0);
  Serial.println("selesai");
}

// Tegangan mentah pin ADC (atenuasi 11 dB, kalibrasi eFuse). Untuk bring-up pembagi baterai & deteksi charge.
static void adcReport() {
  uint32_t b = 0, c = 0;
  for (int i = 0; i < 16; i++) { b += analogReadMilliVolts(1); c += analogReadMilliVolts(4); }
  b /= 16; c /= 16;
  Serial.printf("GPIO1 %lu mV -> baterai ~%.2f V (pembagi %.3f)\r\n", (unsigned long)b, b * battery::divider() / 1000.f,
                (double)battery::divider());
  Serial.printf("GPIO4 %lu mV -> %s\r\n", (unsigned long)c,
                c > 2100 ? "charger dicolok" : c < 300 ? "charger dicabut" : "di tengah (cek wiring / pembagi)");
  // Diagnostik kalibrasi: nilai mentah 12-bit + sumber kalibrasi yang dipakai IDF
  uint32_t r = 0;
  for (int i = 0; i < 16; i++) r += analogRead(1);
  r /= 16;
  esp_adc_cal_characteristics_t ch;
  esp_adc_cal_value_t v = esp_adc_cal_characterize(ADC_UNIT_1, ADC_ATTEN_DB_11, ADC_WIDTH_BIT_12, 1100, &ch);
  Serial.printf("GPIO1 mentah %lu/4095 | kalibrasi %s (eFuse TP %s) | rev chip %d\r\n", (unsigned long)r,
                v == ESP_ADC_CAL_VAL_EFUSE_TP ? "eFuse two-point" : v == ESP_ADC_CAL_VAL_EFUSE_VREF ? "eFuse Vref" : "Vref bawaan",
                esp_adc_cal_check_efuse(ESP_ADC_CAL_VAL_EFUSE_TP) == ESP_OK ? "ada" : "tidak ada", ESP.getChipRevision());
}

// Status baterai + kalibrasi pembagi terhadap multimeter: `batt cal 4.20` (tegangan sel, saklar ON)
static void battCmd(const char* arg) {
  if (!strncasecmp(arg, "cal", 3)) {
    const char* v = arg + 3;
    while (*v == ' ') v++;
    if (!strcasecmp(v, "reset")) {
      battery::resetCalibration();
      Serial.printf("kalibrasi dihapus, pembagi bawaan %.3f\r\n", (double)battery::divider());
    } else if (battery::calibrate(atof(v))) {
      Serial.printf("kalibrasi tersimpan: pembagi %.3f\r\n", (double)battery::divider());
    } else {
      Serial.println("gagal: batt cal <3.0..4.5> (volt sel dari multimeter, saklar ON) | batt cal reset");
      return;
    }
  }
  Serial.printf("baterai %.3f V (%d%%) | GPIO%d %u mV x pembagi %.3f (%s)\r\n", (double)battery::volts(),
                battery::percent(), PIN_BATT, battery::pinMv(), (double)battery::divider(),
                battery::calibrated() ? "kalibrasi" : "bawaan");
  Serial.printf("charger %s (GPIO%d %u mV) | lemah %s | kritis %s | daya luar %s\r\n",
                battery::charging() ? "dicolok" : "tidak", PIN_CHG, battery::chgMv(), battery::low() ? "ya" : "tidak",
                battery::critical() ? "ya" : "tidak", battery::externalPower() ? "ya" : "tidak");
}

// Rekam level mentah pin tombol (bring-up sensor sentuh): tiap perubahan dicetak dengan lamanya. Blocking.
static void btnRaw(const char* arg) {
  int sec = constrain(atoi(arg) > 0 ? atoi(arg) : 10, 1, 60);
  Serial.printf("rekam GPIO%d %d dtk (aktif %s)\r\n", PIN_BTN, sec, BTN_ACTIVE_LOW ? "LOW" : "HIGH");
  int last = digitalRead(PIN_BTN);
  uint32_t t0 = millis(), since = t0;
  Serial.printf("  awal %s\r\n", last ? "HIGH" : "LOW");
  while ((int32_t)(millis() - t0) < sec * 1000) {
    int v = digitalRead(PIN_BTN);
    if (v != last) {
      uint32_t now = millis();
      Serial.printf("  %6lu ms: %s -> %s (setelah %lu ms)\r\n", (unsigned long)(now - t0), last ? "HIGH" : "LOW",
                    v ? "HIGH" : "LOW", (unsigned long)(now - since));
      last = v; since = now;
    }
    delay(1);
  }
  Serial.println("selesai");
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
  } else if (!strcasecmp(line, "roll")) {
    static const char* const D[] = {"1d6", "2d6", "d4", "d8", "d10", "d12", "d20", "koin"};
    int32_t id = 255;
    for (uint8_t i = 0; i < 8; i++) if (*arg && !strcasecmp(arg, D[i])) id = i;
    events::post(EV_ROLL, id);
  } else if (!strcasecmp(line, "phone")) events::post(EV_FIND_PHONE, 1);
  else if (!strcasecmp(line, "notif")) {
    if (!strcasecmp(arg, "clear")) { notifstore::clear(); events::post(EV_NOTIF, 0); return; }
    static uint32_t nextId = 0xC0DE0000;
    Notif n;
    n.id = nextId++;
    char* parts[3] = {arg, nullptr, nullptr};
    for (uint8_t i = 1; i < 3; i++) { char* p = parts[i - 1] ? strchr(parts[i - 1], '|') : nullptr; if (p) { *p = 0; parts[i] = p + 1; } }
    strlcpy(n.app, parts[0] && *parts[0] ? parts[0] : "Console", sizeof(n.app));
    strlcpy(n.title, parts[1] ? parts[1] : "Notifikasi uji", sizeof(n.title));
    strlcpy(n.body, parts[2] ? parts[2] : "Halo dari console Lokana.", sizeof(n.body));
    events::post(EV_NOTIF, notifstore::upsert(n) ? 1 : 0);
  } else if (!strcasecmp(line, "call")) {
    bool stop = !strcasecmp(arg, "stop");
    notifstore::setCall(!stop, stop ? nullptr : (*arg ? arg : "Ibu"));
    events::post(EV_CALL, stop ? 1 : 0);
  }
  else if (!strcasecmp(line, "img")) {
    Anim a;                                       // animasi uji: papan catur bergeser, 8 bingkai
    a.w = SCREEN_W; a.h = SCREEN_H; a.frames = 8; a.frameMs = 120; a.durationS = 5;
    if (a.alloc()) {
      const int bw = a.w / 8;
      for (uint8_t f = 0; f < a.frames; f++)
        for (int y = 0; y < a.h; y++)
          for (int xb = 0; xb < bw; xb++)
            a.frame(f)[y * bw + xb] = (((y + f) / 8 + xb) % 2) ? 0xFF : 0x00;
      imgstore::current().swap(a);
      events::post(EV_BITMAP);
    }
  } else if (!strcasecmp(line, "splash")) events::post(EV_SPLASH, atoi(arg));   // splash [ms]
  else if (!strcasecmp(line, "guide")) events::post(EV_GUIDE, atoi(arg));         // guide [ms]
  else if (!strcasecmp(line, "left")) events::post(EV_LEFT, strcmp(arg, "0") ? 1 : 0);   // left [0]
  else if (!strcasecmp(line, "name")) {
    if (*arg) lklink::rename(!strcmp(arg, "-") ? "" : arg);   // "name -" = kembali ke bawaan
    Serial.printf("nama Bluetooth: %s\r\n", lklink::deviceName());
  }
  else if (!strcasecmp(line, "text")) {
    TextMsg m;
    strlcpy(m.text, arg, sizeof(m.text));
    for (char* c = m.text; *c; c++) if (*c == '|') *c = '\n';   // '|' = baris baru
    textstore::setCurrent(m);
    events::post(EV_TEXT);
  } else if (!strcasecmp(line, "find")) {
    events::post(EV_FIND_KEYS, !strcasecmp(arg, "stop") ? 0 : (atoi(arg) > 0 ? atoi(arg) : 10));
  } else if (!strcasecmp(line, "ble")) lklink::printStatus();
  else if (!strcasecmp(line, "ota")) ota::printStatus();
  else if (!strcasecmp(line, "tone")) {
    int hz = atoi(arg);
    const char* sp = strchr(arg, ' ');
    int ms = sp ? atoi(sp + 1) : 500;
    if (hz < 50 || hz > 12000) { Serial.println("tone <50..12000 Hz> [ms]"); return; }
    buzzer::tone(hz, constrain(ms, 20, 5000));
    Serial.printf("nada %d Hz, %d ms\r\n", hz, ms);
  }
  else if (!strcasecmp(line, "sweep")) sweep(arg);
  else if (!strcasecmp(line, "adc")) adcReport();
  else if (!strcasecmp(line, "btnraw")) btnRaw(arg);
  else if (!strcasecmp(line, "batt")) battCmd(arg);
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
    if (len) { buf[len] = 0; lklink::consoleActivity(); Serial.printf("> %s\r\n", buf); handle(buf); len = 0; }
  } else if (c == 8 || c == 127) { if (len) len--; }
  else if (len < sizeof(buf) - 1) buf[len++] = c;
}

}  // namespace console
