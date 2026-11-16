#include "link_internal.h"
#include "link_proto.h"
#include "text_store.h"
#include "bitmap_store.h"
#include "config.h"
#include "core/core.h"
#include "core/events.h"
#include "core/face.h"
#include "core/clock.h"
#include "core/settings.h"
#include "drivers/hw.h"
#include <esp_mac.h>

using namespace lk;
using lklink::Transport;
using lklink::TR_USB;
using lklink::TR_BLE;
using lklink::TR_COUNT;

static char devName[16] = LOKANA_NAME;
static uint32_t rxFrames = 0, txFrames = 0;
static const char* const TR_NAME[TR_COUNT] = {"usb", "ble"};

// Sesi per transport: host sudah HELLO -> boleh dikirimi pesan tanpa diminta.
// button_events (SETTINGS 0x06) hanya berlaku selama sesi.
static bool session[TR_COUNT] = {false, false};
static bool btnEvents[TR_COUNT] = {false, false};
static bool blePrevSecure = false;

// Balasan yang dikirim setelah ACK (DEVICE_INFO untuk HELLO, REPORT untuk SETTINGS)
typedef void (*Reply)(Transport t);
static Reply afterAck = nullptr;

enum SettingKey : uint8_t {
  SK_BRIGHTNESS = 0x01, SK_SOUND = 0x02, SK_SCREEN_TIMEOUT = 0x03, SK_FLIP = 0x04,
  SK_DEVICE_NAME = 0x05, SK_BUTTON_EVENTS = 0x06,
};
enum SettingsOp : uint8_t { SO_GET = 0, SO_SET = 1, SO_REPORT = 2 };

static void endSession(Transport t) { session[t] = false; btnEvents[t] = false; }

// ---------------- Kirim ----------------
static void ack(Transport t, uint8_t seq, uint8_t type, uint8_t status) {
  uint8_t p[2] = {type, status};
  lklink::send(t, T_ACK, seq, p, sizeof(p));
}

// Kirim ke semua host yang sedang dalam sesi
static void broadcast(uint8_t type, const uint8_t* p, uint16_t n, bool onlyButtons = false) {
  for (uint8_t t = 0; t < TR_COUNT; t++)
    if (session[t] && (!onlyButtons || btnEvents[t])) lklink::send((Transport)t, type, 0, p, n);
}

static void sendDeviceInfo(Transport t) {
  uint8_t p[64];
  Writer w(p, sizeof(p));
  int bat = battery::percent();
  uint8_t flags = 0;
  if (bat < 0) flags |= 1 << 0;            // tanpa sensor baterai = pasti dari USB
  if (lklink::bondCount() > 0) flags |= 1 << 2;
  uint32_t caps = CAP_CUSTOM_TEXT | CAP_DICE | CAP_FIND_PHONE;
  if (bmpstore::ready()) caps |= CAP_BITMAP;
#if PIN_BUZZER >= 0
  caps |= CAP_BUZZER;
#endif
  w.u8(PROTO_VER);
  w.u8(DEVICE_TYPE);
  w.str(FW_VERSION);
  w.u16(SCREEN_W);
  w.u16(SCREEN_H);
  w.u8(bat < 0 ? 255 : (uint8_t)bat);
  w.u8(flags);
  w.u32(caps);
  w.str(lklink::ownerName());
  lklink::send(t, T_DEVICE_INFO, 0, p, w.len());
}

static uint16_t buildReport(uint8_t* p, uint16_t cap, Transport t) {
  Settings& s = settings::get();
  Writer w(p, cap);
  uint16_t to = settings::screenTimeoutS();
  w.u8(SO_REPORT);
  w.u8(SK_BRIGHTNESS);    w.u8(1); w.u8(s.brightness);
  w.u8(SK_SOUND);         w.u8(1); w.u8(s.sound ? 1 : 0);
  w.u8(SK_SCREEN_TIMEOUT); w.u8(2); w.u16(to);
  w.u8(SK_FLIP);          w.u8(1); w.u8(s.flip ? 1 : 0);
  w.u8(SK_DEVICE_NAME);   w.str(s.name);          // str = len u8 + isi, sama dengan TLV
  w.u8(SK_BUTTON_EVENTS); w.u8(1); w.u8(btnEvents[t] ? 1 : 0);
  return w.len();
}

static void sendReport(Transport t) {
  uint8_t p[64];
  lklink::send(t, T_SETTINGS, 0, p, buildReport(p, sizeof(p), t));
}

// ---------------- Handler pesan (H->D) ----------------
static uint8_t onHello(Transport t, Reader& r) {
  uint8_t ver = r.u8();
  if (!r.ok()) return ST_BAD_PAYLOAD;
  uint8_t client = r.has() ? r.u8() : 0;
  char name[40] = "";
  if (r.has()) r.str(name, sizeof(name));
  Serial.printf("[link] %s: HELLO proto=%u client=%u \"%s\"\r\n", TR_NAME[t], ver, client, name);
  endSession(t);                                  // HELLO = sesi baru, button_events kembali mati
  session[t] = true;
  char msg[32];
  snprintf(msg, sizeof(msg), "%.24s", name[0] ? name : (t == TR_BLE ? "HP" : "USB"));
  events::post(EV_TOAST, 0, msg);
  afterAck = sendDeviceInfo;
  return ST_OK;
}

static uint8_t onTimeSync(Reader& r) {
  uint32_t epoch = r.u32();
  if (!r.ok() || epoch < 1700000000UL) return ST_BAD_PAYLOAD;
  if (r.has()) clockx::setTzOffset(r.i16());   // field akhir opsional: tanpa tz = zona lama
  clockx::setEpoch((time_t)epoch);
  return ST_OK;
}

// SET: periksa semua item dulu, baru terapkan (item rusak = tidak ada yang berubah)
static uint8_t onSettings(Transport t, Reader& r) {
  uint8_t op = r.u8();
  if (!r.ok()) return ST_BAD_PAYLOAD;
  if (op == SO_GET) { afterAck = sendReport; return ST_OK; }
  if (op == SO_REPORT) return ST_BAD_PAYLOAD;
  if (op != SO_SET) return ST_NOT_SUPPORTED;

  Reader check = r;
  while (check.has()) {
    check.u8();
    uint8_t n = check.u8();
    check.bytes(n);
    if (!check.ok()) return ST_BAD_PAYLOAD;
  }
  Settings& s = settings::get();
  bool display = false, changed = false;
  while (r.has()) {
    uint8_t key = r.u8(), n = r.u8();
    const uint8_t* v = r.bytes(n);
    uint16_t val = n >= 2 ? (uint16_t)(v[0] | v[1] << 8) : (n ? v[0] : 0);
    switch (key) {
      case SK_BRIGHTNESS:     if (n) { s.brightness = min<uint8_t>(v[0], 2); display = true; } break;
      case SK_SOUND:          if (n) s.sound = v[0] != 0; break;
      case SK_SCREEN_TIMEOUT: if (n) settings::setScreenTimeoutS(val); break;
      case SK_FLIP:           if (n) { s.flip = v[0] != 0; display = true; } break;
      case SK_DEVICE_NAME:    toAscii(v, n, s.name, sizeof(s.name)); break;
      case SK_BUTTON_EVENTS:  if (n) btnEvents[t] = v[0] != 0; continue;   // sesi saja, tidak disimpan
      default: continue;                          // key dari versi lebih baru: abaikan
    }
    changed = true;
  }
  if (changed) settings::save();
  if (display) events::post(EV_SETTINGS);
  afterAck = sendReport;
  return ST_OK;
}

static uint8_t onExpression(Reader& r) {
  uint8_t e = r.u8();
  if (!r.ok()) return ST_BAD_PAYLOAD;
  uint16_t hold = r.has() ? r.u16() : 0;
  if (e >= EXP_COUNT) return ST_NOT_SUPPORTED;   // ID dari versi firmware lebih baru
  events::post(EV_EXPRESSION, (int32_t)e | ((int32_t)hold << 8));
  return ST_OK;
}

static uint8_t onDice(Reader& r) {
  uint8_t op = r.u8();
  if (!r.ok() || op != 0) return ST_BAD_PAYLOAD;  // op 1 (hasil) hanya D->H
  uint8_t dice = r.has() ? r.u8() : 255;
  if (dice != 255 && dice > 7) return ST_NOT_SUPPORTED;
  events::post(EV_ROLL, dice);
  return ST_OK;
}

static uint8_t onGoto(Reader& r) {
  char name[32];
  r.str(name, sizeof(name));
  if (!r.ok() || !name[0]) return ST_BAD_PAYLOAD;
  for (uint8_t i = 0; i < core::moduleCount(); i++) {
    Module* m = core::moduleAt(i);
    if (!m->hidden() && !strcasecmp(m->name(), name)) { events::post(EV_GOTO, 0, m->name()); return ST_OK; }
  }
  return ST_ERROR;                                // modul tidak ada
}

static uint8_t onFindKeys(Reader& r) {
  uint8_t op = r.u8();
  if (!r.ok()) return ST_BAD_PAYLOAD;
  uint8_t dur = r.has() ? r.u8() : 0;
  if (dur == 0) dur = 30;
  events::post(EV_FIND_KEYS, op ? dur : 0);
  return ST_OK;
}

static uint8_t onFindPhone(Reader& r) {
  uint8_t op = r.u8();
  if (!r.ok() || op != 0) return ST_BAD_PAYLOAD;  // dari HP hanya "sudah ditemukan"
  events::post(EV_FIND_PHONE, 0);
  return ST_OK;
}

static uint8_t onCustomText(Reader& r) {
  TextMsg m;
  m.style = r.u8();
  m.size = r.u8();
  m.durationS = r.u16();
  uint8_t slot = r.u8();
  r.str(m.text, sizeof(m.text), true);
  if (!r.ok() || slot > textstore::SLOTS) return ST_BAD_PAYLOAD;
  if (m.style > 2) m.style = 0;                   // gaya dari versi lebih baru -> diam
  if (m.size > 3) m.size = 0;
  if (slot == 0) {
    textstore::setCurrent(m);
    events::post(EV_TEXT);
    return ST_OK;
  }
  if (!textstore::save(slot, m)) return ST_ERROR;
  char msg[24];
  snprintf(msg, sizeof(msg), m.text[0] ? "Disimpan: slot %u" : "Slot %u dihapus", slot);
  events::post(EV_TOAST, 0, msg);
  return ST_OK;
}

static uint8_t onBitmap(Reader& r) {
  static BitmapMsg m;                             // 1 KB: jangan di stack
  uint8_t op = r.u8(), slot = r.u8();
  m.durationS = r.u16();
  m.x = r.i16(); m.y = r.i16();
  m.w = r.u8(); m.h = r.u8();
  if (!r.ok()) return ST_BAD_PAYLOAD;
  if (op > 1) return ST_NOT_SUPPORTED;
  if (m.w > 128 || m.h > 64) return ST_BAD_PAYLOAD;
  if (op == 1 && (slot < 1 || slot > bmpstore::SLOTS)) return ST_BAD_PAYLOAD;
  const uint8_t* d = r.bytes(m.bytes());          // byte berlebih diabaikan
  if (!d) return ST_BAD_PAYLOAD;
  memcpy(m.data, d, m.bytes());
  if (op == 0) {
    if (m.empty()) return ST_BAD_PAYLOAD;
    bmpstore::current() = m;
    events::post(EV_BITMAP);
    return ST_OK;
  }
  if (!bmpstore::save(slot, m)) return ST_ERROR;
  char msg[24];
  snprintf(msg, sizeof(msg), m.empty() ? "Gambar %u dihapus" : "Gambar: slot %u", slot);
  events::post(EV_TOAST, 0, msg);
  return ST_OK;
}

namespace lklink {

void dispatch(Transport t, uint8_t type, uint8_t seq, const uint8_t* p, uint16_t n, bool tooBig) {
  rxFrames++;
  if (type == T_ACK) return;                      // device belum pernah minta ACK; abaikan
  afterAck = nullptr;
  uint8_t st;
  if (tooBig) st = ST_BAD_PAYLOAD;
  else {
    Reader r(p, n);
    switch (type) {
      case T_HELLO:       st = onHello(t, r); break;
      case T_TIME_SYNC:   st = onTimeSync(r); break;
      case T_SETTINGS:    st = onSettings(t, r); break;
      case T_EXPRESSION:  st = onExpression(r); break;
      case T_DICE:        st = onDice(r); break;
      case T_GOTO:        st = onGoto(r); break;
      case T_FIND_KEYS:   st = onFindKeys(r); break;
      case T_FIND_PHONE:  st = onFindPhone(r); break;
      case T_CUSTOM_TEXT: st = onCustomText(r); break;
      case T_BITMAP:      st = onBitmap(r); break;
      // Dikenal, tapi belum ada di firmware ini / arahnya hanya D->H
      case T_DEVICE_INFO: case T_OTA: case T_BUTTON:
      case T_NOTIF: case T_NAV: case T_PC_STATS: case T_MEETING: case T_PHONE_STATS: case T_CALL:
      case T_WIFI_PROV: case T_WIFI_STATUS:
        st = ST_NOT_SUPPORTED; break;
      default: st = ST_UNKNOWN_TYPE; break;
    }
  }
  if (type != T_HELLO || st != ST_OK)
    Serial.printf("[link] %s: %s seq=%u len=%u -> %u\r\n", TR_NAME[t], typeName(type), seq, n, st);
  if (seq) ack(t, seq, type, st);
  if (st == ST_OK && afterAck) afterAck(t);
  afterAck = nullptr;
}

void send(Transport t, uint8_t type, uint8_t seq, const uint8_t* payload, uint16_t len) {
  static uint8_t f[4 + MAX_PAYLOAD];
  if (len > MAX_PAYLOAD) return;
  f[0] = type; f[1] = seq; f[2] = len & 0xFF; f[3] = len >> 8;
  if (len) memcpy(f + 4, payload, len);
  if (t == TR_USB) link_usb::write(f, len + 4);
#ifndef WOKWI_SIM
  else if (!link_ble::write(f, len + 4)) return;
#else
  else return;
#endif
  txFrames++;
}

// ---------------- Pesan D->H tanpa diminta ----------------
void reportDice(uint8_t dice, const uint8_t* values, uint8_t count) {
  uint8_t p[8];
  Writer w(p, sizeof(p));
  w.u8(1); w.u8(dice); w.u8(count); w.bytes(values, count);
  broadcast(T_DICE, p, w.len());
}

void reportButton(uint8_t gesture, const char* module) {
  uint8_t p[40];
  Writer w(p, sizeof(p));
  w.u8(gesture); w.str(module);
  broadcast(T_BUTTON, p, w.len(), true);
}

void reportSettings() {
  uint8_t p[64];
  for (uint8_t t = 0; t < TR_COUNT; t++)
    if (session[t]) send((Transport)t, T_SETTINGS, 0, p, buildReport(p, sizeof(p), (Transport)t));
}

bool phoneReady() { return session[TR_BLE]; }

bool findPhone(bool ring) {
  if (!phoneReady()) return false;
  uint8_t op = ring ? 1 : 0;
  send(TR_BLE, T_FIND_PHONE, 0, &op, 1);
  return true;
}

void consoleActivity() {
  if (session[TR_USB]) Serial.println("[link] usb: console dipakai, pesan tanpa diminta dihentikan sampai HELLO");
  endSession(TR_USB);
}

void begin() {
  uint8_t mac[6] = {0};
  esp_read_mac(mac, ESP_MAC_BT);
  snprintf(devName, sizeof(devName), "%s-%02X%02X", LOKANA_NAME, mac[4], mac[5]);
  bmpstore::begin();
  link_usb::begin();
#ifndef WOKWI_SIM
  link_ble::begin(devName);                       // Wokwi tidak mendukung BLE
#endif
}

void update(uint32_t now) {
  link_usb::update(now);
#ifndef WOKWI_SIM
  link_ble::update(now);
  bool sec = link_ble::secure();
  if (blePrevSecure && !sec) endSession(TR_BLE);  // HP putus: sesi & button_events selesai
  blePrevSecure = sec;
#endif
}

const char* deviceName() { return devName; }
const char* ownerName() { return settings::get().name[0] ? settings::get().name : devName; }

const char* bleStatus() {
#ifdef WOKWI_SIM
  return "mati";
#else
  if (link_ble::pairing()) return "pairing";
  if (link_ble::secure()) return "tersambung";
  if (link_ble::connected()) return "menyambung";
  return "iklan";
#endif
}

uint8_t bondCount() {
#ifdef WOKWI_SIM
  return 0;
#else
  return link_ble::bonds();
#endif
}

void forgetBonds() {
#ifndef WOKWI_SIM
  link_ble::forget();
#endif
  Serial.println("[link] semua pairing dihapus");
}

void printStatus() {
  Serial.printf("  nama %s (%s) | BLE %s | bond %u | MTU %u | sesi usb=%u ble=%u | tombol usb=%u ble=%u | frame masuk %lu keluar %lu\r\n",
                devName, ownerName(), bleStatus(), bondCount(),
#ifdef WOKWI_SIM
                0,
#else
                link_ble::mtu(),
#endif
                session[TR_USB], session[TR_BLE], btnEvents[TR_USB], btnEvents[TR_BLE], rxFrames, txFrames);
}

}  // namespace lklink
