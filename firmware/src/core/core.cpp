#include "core.h"
#include "config.h"
#include "core/settings.h"
#include "core/clock.h"
#include "drivers/display.h"
#include "drivers/buzzer.h"
#include "drivers/hw.h"
#include "services/link.h"

static const uint8_t MAX_MODULES = 16;
static Module* mods[MAX_MODULES];
static uint8_t count = 0, active = 0, prevActive = 0;

static bool menuOpen = false, infoOpen = false, screenIsOn = true;
static uint8_t menuIdx = 0;
static uint32_t menuLast = 0, lastFrame = 0, lastInput = 0;
static char toastText[32] = {0};
static uint32_t toastUntil = 0;
static Gesture injected = G_NONE;
static bool swallowNext = false;
static uint32_t loopPrev = 0, loopMax = 0, loopMaxShown = 0, loopWin = 0;

// ---------------- Menu ----------------
enum MenuItem : uint8_t { MI_PHONE, MI_BRIGHT, MI_SOUND, MI_SCREEN, MI_FLIP, MI_FORGET, MI_INFO, MI_EXIT, MI_COUNT };
static const char* const MENU_LABEL[MI_COUNT] = {"Cari HP", "Kecerahan", "Suara", "Layar mati", "Putar layar", "Lupakan HP", "Info", "Keluar"};
static bool settingsDirty = false;

static const char* menuValue(uint8_t i) {
  Settings& s = settings::get();
  switch (i) {
    case MI_BRIGHT: return BRIGHTNESS_LABEL[s.brightness];
    case MI_SOUND:  return s.sound ? "On" : "Off";
    case MI_SCREEN: return SCREEN_TIMEOUT_LABEL[s.screenIdx];
    case MI_FLIP:   return s.flip ? "On" : "Off";
    case MI_PHONE:
    case MI_FORGET:
    case MI_INFO:   return ">";
    default:        return "";
  }
}

static void applySettings() {
  display::setBrightness(settings::get().brightness);
  display::setFlip(settings::get().flip);
}

static void closeMenu() {
  menuOpen = infoOpen = false;
  if (settingsDirty) { settings::save(); lklink::reportSettings(); settingsDirty = false; }
  buzzer::play(MEL_SELECT);
}

static void menuInput(Gesture g) {
  menuLast = millis();
  if (infoOpen) { infoOpen = false; return; }
  Settings& s = settings::get();
  if (g == G_TAP) { menuIdx = (menuIdx + 1) % MI_COUNT; buzzer::play(MEL_MENU); return; }
  if (g == G_DOUBLE || g == G_TRIPLE) { closeMenu(); return; }
  if (g == G_LONG) {
    if (menuIdx >= MI_BRIGHT && menuIdx <= MI_FLIP) settingsDirty = true;
    switch (menuIdx) {
      case MI_PHONE:  closeMenu(); events::post(EV_FIND_PHONE, 1); return;
      case MI_BRIGHT: s.brightness = (s.brightness + 1) % 3; applySettings(); break;
      case MI_SOUND:  s.sound = !s.sound; break;
      case MI_SCREEN: s.screenIdx = (s.screenIdx + 1) % SCREEN_TIMEOUT_COUNT; break;
      case MI_FLIP:   s.flip = !s.flip; applySettings(); break;
      case MI_FORGET: lklink::forgetBonds(); core::toast("Pairing dihapus", 1200); break;
      case MI_INFO:   infoOpen = true; break;
      case MI_EXIT:   closeMenu(); return;
    }
    buzzer::play(MEL_SELECT);
  }
}

// Bilah judul terbalik (putih) setinggi 10 px: judul kiri, teks kanan opsional
static void drawHeader(Adafruit_GFX& g, const char* title, const char* right) {
  g.fillRect(0, 0, SCREEN_W, 10, 1);
  g.setTextSize(1); g.setTextColor(0);
  g.setCursor(2, 1); g.print(title);
  if (right) { g.setCursor(SCREEN_W - 2 - display::textWidth(right), 1); g.print(right); }
  g.setTextColor(1);
}

// 128x64: 4 baris sekaligus (yang terpilih dibalik warnanya). 128x32: 1 baris.
static const int MENU_ROW_H = 10, MENU_TOP = 11;
static const int MENU_ROWS = (SCREEN_H - 22) / MENU_ROW_H > 0 ? (SCREEN_H - 22) / MENU_ROW_H : 1;

static void drawMenu(Adafruit_GFX& g) {
  char pos[8]; snprintf(pos, sizeof(pos), "%d/%d", menuIdx + 1, MI_COUNT);
  drawHeader(g, "MENU", pos);
  uint8_t top = menuIdx < MENU_ROWS ? 0 : menuIdx - MENU_ROWS + 1;
  for (uint8_t r = 0; r < MENU_ROWS && top + r < MI_COUNT; r++) {
    uint8_t i = top + r;
    int y = MENU_TOP + r * MENU_ROW_H;
    bool sel = i == menuIdx;
    if (sel && MENU_ROWS > 1) { g.fillRect(0, y, SCREEN_W, MENU_ROW_H - 1, 1); g.setTextColor(0); }
    g.setCursor(2, y + 1); g.print(MENU_LABEL[i]);
    const char* v = menuValue(i);
    g.setCursor(SCREEN_W - 2 - display::textWidth(v), y + 1); g.print(v);
    g.setTextColor(1);
  }
  g.setCursor(2, SCREEN_H - 8); g.print("tap:lanjut tahan:ubah");
}

static void drawInfo(Adafruit_GFX& g) {
  char l[5][24];
  uint8_t n = 0;
  snprintf(l[n++], 24, "%s v%s", LOKANA_OS, FW_VERSION);
  int p = battery::percent();
  if (p < 0) snprintf(l[n++], 24, "Baterai: USB");
  else snprintf(l[n++], 24, "Baterai: %.2fV %d%%", battery::volts(), p);
  g.setTextSize(1); g.setTextColor(1);
#if SCREEN_H >= 64
  uint32_t up = millis() / 1000;
  snprintf(l[n++], 24, "Jam: %s", clockx::status());
  snprintf(l[n++], 24, "Aktif: %luj %02lum %02lud", up / 3600, (up / 60) % 60, up % 60);
  snprintf(l[n++], 24, "BLE: %s", lklink::bleStatus());
  char who[16];
  snprintf(who, sizeof(who), "%.15s", lklink::ownerName());
  drawHeader(g, "INFO", who);
  for (uint8_t i = 0; i < n; i++) { g.setCursor(0, 13 + i * 10); g.print(l[i]); }
#else
  snprintf(l[n++], 24, "Jam:%s %lus", clockx::status(), millis() / 1000);
  for (uint8_t i = 0; i < n; i++) { g.setCursor(0, i * 11); g.print(l[i]); }
#endif
}

static void drawToast(Adafruit_GFX& g) {
  const int h = SCREEN_H >= 64 ? 18 : 14;
  int w = min(display::textWidth(toastText) + 10, (int)SCREEN_W);
  int x = (SCREEN_W - w) / 2, y = (SCREEN_H - h) / 2;
  g.fillRoundRect(x, y, w, h, 3, 0);
  g.drawRoundRect(x, y, w, h, 3, 1);
  g.setTextSize(1); g.setTextColor(1);
  g.setCursor(x + 5, y + (h - 7) / 2); g.print(toastText);
}

// ---------------- Perpindahan modul ----------------
static void switchTo(uint8_t i, bool announce) {
  if (i >= count) return;
  if (i != active) {
    if (!mods[active]->hidden()) prevActive = active;
    mods[active]->exit(); active = i; mods[active]->enter();
  }
  if (announce) core::toast(mods[active]->name(), 700);
}

namespace core {

void begin() {
  applySettings();
  if (count) mods[0]->enter();
  lastInput = millis();
}

void addModule(Module* m) { if (count < MAX_MODULES) mods[count++] = m; }
uint8_t moduleCount() { return count; }
Module* moduleAt(uint8_t i) { return i < count ? mods[i] : nullptr; }
Module* current() { return count ? mods[active] : nullptr; }
bool screenOn() { return screenIsOn; }

bool goTo(const char* name) {
  for (uint8_t i = 0; i < count; i++)
    if (!strcasecmp(mods[i]->name(), name)) { menuOpen = false; switchTo(i, true); wake(); return true; }
  return false;
}

void next() {
  uint8_t i = active;
  do { i = (i + 1) % count; } while (mods[i]->hidden() && i != active);
  switchTo(i, true);
  buzzer::play(MEL_MENU);
}

void back() { switchTo(prevActive < count ? prevActive : 0, false); }

void openMenu() { menuOpen = true; infoOpen = false; menuIdx = 0; menuLast = millis(); buzzer::play(MEL_SELECT); }

void toast(const char* text, uint16_t ms) {
  strlcpy(toastText, text, sizeof(toastText));
  toastUntil = millis() + ms;
}

void wake() {
  lastInput = millis();
  if (!screenIsOn) {
    screenIsOn = true;
    display::power(true);
    buzzer::play(MEL_WAKE);
    swallowNext = true;            // gestur dari tekanan pembangun tidak diteruskan
  }
}

void sleepScreen() {
  if (!screenIsOn) return;
  buzzer::play(MEL_SLEEP);
  display::clear(); display::show();
  display::power(false);
  screenIsOn = false;
  menuOpen = false;
}

void injectGesture(Gesture g) { injected = g; }

uint32_t loopMaxMs() { return loopMaxShown; }

void loop() {
  uint32_t now = millis();
  if (loopPrev) { uint32_t d = now - loopPrev; if (d > loopMax) loopMax = d; }
  loopPrev = now;
  if (now - loopWin >= 1000) { loopMaxShown = loopMax; loopMax = 0; loopWin = now; }
  Gesture g = button::update(now);
  if (injected != G_NONE) { g = injected; injected = G_NONE; }
  buzzer::update(now);
  led::update(now);
  battery::update(now);
  clockx::update(now);

  // Layar mati: tekanan apa pun membangunkan
  if (!screenIsOn) {
    if (g != G_NONE || button::pressed()) wake();
    Event e;
    // Event (pesan dari HP/PC) membangunkan layar; sentuhan berikutnya tidak ditelan
    while (events::poll(e)) { wake(); swallowNext = false; for (uint8_t i = 0; i < count; i++) mods[i]->event(e); }
    delay(10);
    return;
  }
  if (swallowNext && g != G_NONE) { swallowNext = false; g = G_NONE; }
  if (swallowNext && (int32_t)(now - lastInput) > 1500) swallowNext = false;

  // Gestur
  if (g != G_NONE) {
    lastInput = now;
    led::pulse(30);
    Serial.printf("[btn] %s\r\n", button::name(g));
    if (!menuOpen) lklink::reportButton((uint8_t)g, mods[active]->name());   // G_TAP..G_LONG = 1..4
    if (menuOpen) menuInput(g);
    else if (g == G_DOUBLE) next();
    else if (g == G_TRIPLE) openMenu();
    else if (!mods[active]->input(g) && g == G_LONG) sleepScreen();
  }
  if (menuOpen && (int32_t)(now - menuLast) > 20000) closeMenu();

  // Event
  Event e;
  while (events::poll(e)) {
    lastInput = now;
    if (e.type == EV_GOTO) { goTo(e.text); continue; }
    if (e.type == EV_TOAST) { toast(e.text); continue; }
    if (e.type == EV_SETTINGS) { applySettings(); continue; }
    if (e.type == EV_EXPRESSION) switchTo(0, false);
    for (uint8_t i = 0; i < count; i++) mods[i]->event(e);
  }

  mods[active]->update(now);

  // Layar mati otomatis
  uint32_t to = settings::screenTimeoutMs();
  if (to && !menuOpen && !mods[active]->keepAwake() && (int32_t)(now - lastInput) > (int32_t)to) { sleepScreen(); return; }

  // Gambar
  if (now - lastFrame >= FRAME_MS) {
    lastFrame = now;
    Adafruit_GFX& gfx = display::gfx();
    display::clear();
    if (menuOpen) { if (infoOpen) drawInfo(gfx); else drawMenu(gfx); }
    else {
      mods[active]->render(gfx, now);
      if ((int32_t)(toastUntil - now) > 0) drawToast(gfx);
    }
    display::show();
  }
  delay(1);
}

}  // namespace core
