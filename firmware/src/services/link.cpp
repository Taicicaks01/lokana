#include "link_internal.h"
#include "link_proto.h"
#include "text_store.h"
#include "config.h"
#include "core/core.h"
#include "core/events.h"
#include "core/face.h"
#include "core/clock.h"
#include "drivers/hw.h"
#include <esp_mac.h>

using namespace lk;

static char devName[16] = LOKANA_NAME;
static uint32_t rxFrames = 0, txFrames = 0;
static const char* const TR_NAME[lklink::TR_COUNT] = {"usb", "ble"};

// ---------------- Kirim ----------------
static void ack(lklink::Transport t, uint8_t seq, uint8_t type, uint8_t status) {
  uint8_t p[2] = {type, status};
  lklink::send(t, T_ACK, seq, p, sizeof(p));
}

static void sendDeviceInfo(lklink::Transport t) {
  uint8_t p[64];
  Writer w(p, sizeof(p));
  int bat = battery::percent();
  uint8_t flags = 0;
  if (bat < 0) flags |= 1 << 0;            // tanpa sensor baterai = pasti dari USB
  if (link_ble::bonds() > 0) flags |= 1 << 2;
  uint32_t caps = CAP_CUSTOM_TEXT;
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
  w.str(devName);
  lklink::send(t, T_DEVICE_INFO, 0, p, w.len());
}

// ---------------- Handler pesan (H->D) ----------------
static uint8_t onHello(lklink::Transport t, Reader& r) {
  uint8_t ver = r.u8();
  if (!r.ok()) return ST_BAD_PAYLOAD;
  uint8_t client = r.has() ? r.u8() : 0;
  char name[40] = "";
  if (r.has()) r.str(name, sizeof(name));
  Serial.printf("[link] %s: HELLO proto=%u client=%u \"%s\"\r\n", TR_NAME[t], ver, client, name);
  char msg[32];
  snprintf(msg, sizeof(msg), "%.24s", name[0] ? name : (t == lklink::TR_BLE ? "HP" : "USB"));
  events::post(EV_TOAST, 0, msg);
  return ST_OK;
}

static uint8_t onTimeSync(Reader& r) {
  uint32_t epoch = r.u32();
  if (!r.ok() || epoch < 1700000000UL) return ST_BAD_PAYLOAD;
  if (r.has()) clockx::setTzOffset(r.i16());   // field akhir opsional: tanpa tz = zona lama
  clockx::setEpoch((time_t)epoch);
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

namespace lklink {

void dispatch(Transport t, uint8_t type, uint8_t seq, const uint8_t* p, uint16_t n, bool tooBig) {
  rxFrames++;
  if (type == T_ACK) return;                      // device belum pernah minta ACK; abaikan
  uint8_t st;
  if (tooBig) st = ST_BAD_PAYLOAD;
  else {
    Reader r(p, n);
    switch (type) {
      case T_HELLO:       st = onHello(t, r); break;
      case T_TIME_SYNC:   st = onTimeSync(r); break;
      case T_EXPRESSION:  st = onExpression(r); break;
      case T_GOTO:        st = onGoto(r); break;
      case T_FIND_KEYS:   st = onFindKeys(r); break;
      case T_CUSTOM_TEXT: st = onCustomText(r); break;
      // Dikenal, tapi belum ada di firmware ini / arahnya D->H
      case T_DEVICE_INFO: case T_SETTINGS: case T_OTA:
      case T_NOTIF: case T_NAV: case T_PC_STATS: case T_MEETING: case T_PHONE_STATS: case T_CALL:
      case T_FIND_PHONE: case T_DICE: case T_BUTTON: case T_BITMAP:
      case T_WIFI_PROV: case T_WIFI_STATUS:
        st = ST_NOT_SUPPORTED; break;
      default: st = ST_UNKNOWN_TYPE; break;
    }
  }
  if (type != T_HELLO || st != ST_OK)
    Serial.printf("[link] %s: %s seq=%u len=%u -> %u\r\n", TR_NAME[t], typeName(type), seq, n, st);
  if (seq) ack(t, seq, type, st);
  if (type == T_HELLO && st == ST_OK) sendDeviceInfo(t);
}

void send(Transport t, uint8_t type, uint8_t seq, const uint8_t* payload, uint16_t len) {
  static uint8_t f[4 + MAX_PAYLOAD];
  if (len > MAX_PAYLOAD) return;
  f[0] = type; f[1] = seq; f[2] = len & 0xFF; f[3] = len >> 8;
  if (len) memcpy(f + 4, payload, len);
  if (t == TR_USB) link_usb::write(f, len + 4);
  else if (!link_ble::write(f, len + 4)) return;
  txFrames++;
}

void begin() {
  uint8_t mac[6] = {0};
  esp_read_mac(mac, ESP_MAC_BT);
  snprintf(devName, sizeof(devName), "%s-%02X%02X", LOKANA_NAME, mac[4], mac[5]);
  link_usb::begin();
#ifndef WOKWI_SIM
  link_ble::begin(devName);                       // Wokwi tidak mendukung BLE
#endif
}

void update(uint32_t now) {
  link_usb::update(now);
#ifndef WOKWI_SIM
  link_ble::update(now);
#endif
}

const char* deviceName() { return devName; }

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
  Serial.printf("  nama %s | BLE %s | bond %u | MTU %u | frame masuk %lu keluar %lu\r\n",
                devName, bleStatus(), bondCount(),
#ifdef WOKWI_SIM
                0,
#else
                link_ble::mtu(),
#endif
                rxFrames, txFrames);
}

}  // namespace lklink
