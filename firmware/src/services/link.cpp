#include "link_internal.h"
#include "link_proto.h"
#include "text_store.h"
#include "image_store.h"
#include "notif_store.h"
#include "config.h"
#include "core/core.h"
#include "core/events.h"
#include "core/face.h"
#include "core/clock.h"
#include "core/settings.h"
#include "core/oled_text.h"
#include "drivers/hw.h"
#include "drivers/display.h"

using namespace lk;
using lklink::Transport;
using lklink::TR_USB;
using lklink::TR_BLE;
using lklink::TR_COUNT;

static char devName[27] = BLE_NAME_DEFAULT;      // nama yang berlaku (UTF-8): SETTINGS atau bawaan
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
  SK_DEVICE_NAME = 0x05, SK_BUTTON_EVENTS = 0x06, SK_NOTIF_POPUP = 0x07, SK_BOOT_GUIDE = 0x08, SK_LEAVE_ALERT = 0x09,
};
enum SettingsOp : uint8_t { SO_GET = 0, SO_SET = 1, SO_REPORT = 2 };

// Mirror layar (SCREEN) per transport
static struct Mirror {
  uint32_t until = 0;                            // aktif sampai (millis); 0 = mati
  uint16_t intervalMs = 100;
  uint32_t lastCheck = 0, lastSent = 0;
  uint16_t lastCrc = 0;
  bool capture = false;                          // kirim satu FRAME segera
} mirror[TR_COUNT];
static const uint32_t MIRROR_TIMEOUT_MS = 30000, MIRROR_KEEPALIVE_MS = 2000;

static void endSession(Transport t) { session[t] = false; btnEvents[t] = false; mirror[t] = Mirror(); }

static void refreshName() {
  strlcpy(devName, settings::get().name[0] ? settings::get().name : BLE_NAME_DEFAULT, sizeof(devName));
}

// ANIM: animasi yang sedang diterima dari host
static Anim rxAnim;
static uint8_t rxSlot = 0;
static uint32_t rxMask = 0;                      // bit i = bingkai i sudah diterima
static bool rxActive = false;

// Pengiriman galeri ke host (ANIM READ / LIST) dicicil di update() supaya BLE tidak kebanjiran
static struct {
  bool active = false;
  Transport t = TR_USB;
  uint8_t slot = 0;
  int16_t next = -1;                             // -1 BEGIN, 0..n-1 FRAME, n END
  uint32_t at = 0;
  Anim a;
} out;

// Daftar slot teks ke host (TEXT_SLOT LIST): satu ITEM per giliran, slot 1..8
static struct {
  bool active = false;
  Transport t = TR_USB;
  uint8_t next = 1;
  uint32_t at = 0;
} textOut;

// Pengingat ketinggalan (SETTINGS leave_alert): waktu layar Tertinggal dibuka jika HP belum kembali
static uint32_t leaveAt = 0;
static bool leaveShown = false;
static const uint32_t LEAVE_GRACE_MS = 20000, LEAVE_RSSI_MAX_AGE_MS = 5000;
static const int8_t LEAVE_RSSI_NEAR = -70;       // lebih kuat dari ini = HP masih dekat (dimatikan di dekat Lokana)
static const uint16_t REASON_TIMEOUT = 0x208;    // BLE_HS_ERR_HCI_BASE + HCI 0x08 supervision timeout

// UNPAIR lewat BLE: dihapus sesudah ACK terkirim
static uint32_t unpairAt = 0;

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
  uint32_t caps = CAP_NOTIF | CAP_CUSTOM_TEXT | CAP_DICE | CAP_FIND_PHONE;
  if (imgstore::ready()) caps |= CAP_BITMAP | CAP_ANIM;
  caps |= CAP_SCREEN | CAP_TEXT_SLOT;
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

static uint16_t buildReport(uint8_t* p, uint16_t cap, Transport t) {
  Settings& s = settings::get();
  Writer w(p, cap);
  uint16_t to = settings::screenTimeoutS();
  w.u8(SO_REPORT);
  w.u8(SK_BRIGHTNESS);    w.u8(1); w.u8(s.brightness);
  w.u8(SK_SOUND);         w.u8(1); w.u8(s.sound ? 1 : 0);
  w.u8(SK_SCREEN_TIMEOUT); w.u8(2); w.u16(to);
  w.u8(SK_FLIP);          w.u8(1); w.u8(s.flip ? 1 : 0);
  w.u8(SK_DEVICE_NAME);   w.str(devName);         // nama yang berlaku; str = len u8 + isi (TLV)
  w.u8(SK_BUTTON_EVENTS); w.u8(1); w.u8(btnEvents[t] ? 1 : 0);
  w.u8(SK_NOTIF_POPUP);   w.u8(1); w.u8(s.notifPopupS);
  w.u8(SK_BOOT_GUIDE);    w.u8(1); w.u8(s.bootGuide ? 1 : 0);
  w.u8(SK_LEAVE_ALERT);   w.u8(1); w.u8(s.leaveAlert ? 1 : 0);
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
  bool display = false, changed = false, renamed = false;
  while (r.has()) {
    uint8_t key = r.u8(), n = r.u8();
    const uint8_t* v = r.bytes(n);
    uint16_t val = n >= 2 ? (uint16_t)(v[0] | v[1] << 8) : (n ? v[0] : 0);
    switch (key) {
      case SK_BRIGHTNESS:     if (n) { s.brightness = min<uint8_t>(v[0], 2); display = true; } break;
      case SK_SOUND:          if (n) s.sound = v[0] != 0; break;
      case SK_SCREEN_TIMEOUT: if (n) settings::setScreenTimeoutS(val); break;
      case SK_FLIP:           if (n) { s.flip = v[0] != 0; display = true; } break;
      case SK_DEVICE_NAME:    sanitizeUtf8(v, n, s.name, sizeof(s.name) - 1); renamed = true; break;
      case SK_BUTTON_EVENTS:  if (n) btnEvents[t] = v[0] != 0; continue;   // sesi saja, tidak disimpan
      case SK_NOTIF_POPUP:    if (n) s.notifPopupS = settings::clampNotifPopup(v[0]); break;
      case SK_BOOT_GUIDE:     if (n) s.bootGuide = v[0] != 0; break;
      case SK_LEAVE_ALERT:    if (n) { s.leaveAlert = v[0] != 0; if (!s.leaveAlert) leaveAt = 0; } break;
      default: continue;                          // key dari versi lebih baru: abaikan
    }
    changed = true;
  }
  if (changed) settings::save();
  if (display) events::post(EV_SETTINGS);
  if (renamed) lklink::rename(s.name);
  afterAck = sendReport;
  return ST_OK;
}

static uint8_t onNotif(Reader& r) {
  uint8_t op = r.u8();
  uint32_t id = r.u32();
  if (!r.ok()) return ST_BAD_PAYLOAD;
  if (op == 1) {                                  // hapus (id tak dikenal tetap OK)
    if (notifstore::remove(id)) events::post(EV_NOTIF, 0);
    return ST_OK;
  }
  if (op != 0) return ST_NOT_SUPPORTED;
  Notif n;
  n.id = id;
  n.category = r.u8();
  n.flags = r.u8();
  r.str(n.app, sizeof(n.app));
  r.str(n.title, sizeof(n.title));
  r.str(n.body, sizeof(n.body), true);
  if (!r.ok()) return ST_BAD_PAYLOAD;
  bool fresh = notifstore::upsert(n);
  Serial.printf("[notif] %s id=%lu \"%s\"\r\n", fresh ? "baru" : "perbarui", (unsigned long)id, n.app);
  events::post(EV_NOTIF, fresh ? 1 : 0);
  return ST_OK;
}

static uint8_t onCall(Reader& r) {
  uint8_t state = r.u8();
  if (!r.ok()) return ST_BAD_PAYLOAD;
  if (state > 1) return ST_NOT_SUPPORTED;
  char who[41] = "";
  if (r.has()) r.str(who, sizeof(who));
  notifstore::setCall(state == 0, state == 0 ? who : nullptr);
  events::post(EV_CALL, state);
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
    if (m->remoteOpen() && !strcasecmp(m->name(), name)) { events::post(EV_GOTO, 0, m->name()); return ST_OK; }
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
  if (r.ok() && r.has()) m.font = r.u8();            // field akhir opsional (0.5.2)
  if (!r.ok() || slot > textstore::SLOTS) return ST_BAD_PAYLOAD;
  if (m.font >= textstore::FONTS) m.font = 0;       // font dari versi lebih baru -> piksel
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

// ---------------- TEXT_SLOT ----------------
enum TextSlotOp : uint8_t { TS_LIST = 0, TS_ITEM = 1, TS_SHOW = 2 };

static uint8_t onTextSlot(Transport t, Reader& r) {
  uint8_t op = r.u8();
  if (!r.ok()) return ST_BAD_PAYLOAD;
  switch (op) {
    case TS_LIST:
      textOut.active = true; textOut.t = t; textOut.next = 1; textOut.at = millis() + 20;   // sesudah ACK
      return ST_OK;
    case TS_SHOW: {
      uint8_t slot = r.u8();
      uint16_t dur = r.has() ? r.u16() : 0;
      if (!r.ok() || slot < 1 || slot > textstore::SLOTS) return ST_BAD_PAYLOAD;
      TextMsg m;
      if (!textstore::load(slot, m)) return ST_ERROR;
      events::post(EV_TEXT, slot | (int32_t)dur << 8);   // modul Teks membaca slot sendiri
      return ST_OK;
    }
    case TS_ITEM: return ST_BAD_PAYLOAD;            // hanya D->H
    default: return ST_NOT_SUPPORTED;
  }
}

static void pumpTextOut(uint32_t now) {
  if (!textOut.active || (int32_t)(now - textOut.at) < 0) return;
  TextMsg m;
  bool has = textstore::load(textOut.next, m);
  uint8_t p[5 + 1 + sizeof(m.text)];
  Writer w(p, sizeof(p));
  w.u8(TS_ITEM); w.u8(textOut.next);
  w.u8(has ? m.style : 0); w.u8(has ? m.size : 0); w.u8(has ? m.font : 0);
  w.str(has ? m.text : "");
  lklink::send(textOut.t, T_TEXT_SLOT, 0, p, w.len());
  if (++textOut.next > textstore::SLOTS) textOut.active = false;
  textOut.at = now + (textOut.t == TR_BLE ? 40 : 5);
}

static void toastSlot(uint8_t slot, bool removed) {
  char msg[24];
  snprintf(msg, sizeof(msg), removed ? "Gambar %u dihapus" : "Gambar: slot %u", slot);
  events::post(EV_TOAST, 0, msg);
}

// BITMAP = animasi 1 bingkai (galeri yang sama dengan ANIM)
static uint8_t onBitmap(Reader& r) {
  Anim m;
  uint8_t op = r.u8(), slot = r.u8();
  m.durationS = r.u16();
  m.x = r.i16(); m.y = r.i16();
  m.w = r.u8(); m.h = r.u8();
  m.frames = 1;
  if (!r.ok()) return ST_BAD_PAYLOAD;
  if (op > 1) return ST_NOT_SUPPORTED;
  if (m.w > 128 || m.h > 64) return ST_BAD_PAYLOAD;
  if (op == 1 && (slot < 1 || slot > imgstore::SLOTS)) return ST_BAD_PAYLOAD;
  const uint8_t* d = r.bytes(m.frameBytes());     // byte berlebih diabaikan
  if (!d) return ST_BAD_PAYLOAD;
  bool empty = !m.w || !m.h;
  if (op == 0 && empty) return ST_BAD_PAYLOAD;
  if (op == 1 && empty) { if (!imgstore::remove(slot)) return ST_ERROR; toastSlot(slot, true); return ST_OK; }
  if (!m.alloc()) return ST_ERROR;
  memcpy(m.data, d, m.frameBytes());
  if (op == 0) {
    imgstore::current().swap(m);
    events::post(EV_BITMAP);
    return ST_OK;
  }
  if (!imgstore::save(slot, m)) return ST_ERROR;
  toastSlot(slot, false);
  return ST_OK;
}

enum AnimOp : uint8_t {
  AO_BEGIN = 0, AO_FRAME = 1, AO_END = 2, AO_ABORT = 3, AO_READ = 4, AO_LIST = 5, AO_LIST_REPORT = 6,
  AO_DELETE = 7, AO_SHOW = 8,
};

static void sendList(Transport t) {
  uint8_t p[1 + 3 * imgstore::SLOTS];
  Writer w(p, sizeof(p));
  w.u8(AO_LIST_REPORT);
  for (uint8_t s = 1; s <= imgstore::SLOTS; s++) {
    uint8_t f, wd, h;
    imgstore::info(s, f, wd, h);
    w.u8(f); w.u8(wd); w.u8(h);
  }
  lklink::send(t, T_ANIM, 0, p, w.len());
}

static uint8_t onAnim(Transport t, Reader& r) {
  uint8_t op = r.u8();
  if (!r.ok()) return ST_BAD_PAYLOAD;
  if (!imgstore::ready() && op != AO_ABORT) return ST_ERROR;
  switch (op) {
    case AO_BEGIN: {
      rxActive = false;
      rxAnim.release();
      rxSlot = r.u8();
      rxAnim.frames = r.u8();
      rxAnim.frameMs = r.u16();
      rxAnim.loops = r.u8();
      rxAnim.durationS = r.u16();
      rxAnim.x = r.i16(); rxAnim.y = r.i16();
      rxAnim.w = r.u8(); rxAnim.h = r.u8();
      if (!r.ok() || rxSlot > imgstore::SLOTS) return ST_BAD_PAYLOAD;
      if (rxAnim.frameMs < 40) rxAnim.frameMs = 40;
      if (!rxAnim.alloc()) return rxAnim.totalBytes() > Anim::MAX_BYTES || !rxAnim.frames ||
                                  rxAnim.frames > Anim::MAX_FRAMES || !rxAnim.w || rxAnim.w > 128 ||
                                  !rxAnim.h || rxAnim.h > 64 ? ST_BAD_PAYLOAD : ST_ERROR;
      rxMask = 0;
      rxActive = true;
      return ST_OK;
    }
    case AO_FRAME: {
      uint8_t i = r.u8();
      if (!r.ok() || !rxActive || i >= rxAnim.frames) return ST_BAD_PAYLOAD;
      const uint8_t* d = r.bytes(rxAnim.frameBytes());
      if (!d) return ST_BAD_PAYLOAD;
      memcpy(rxAnim.frame(i), d, rxAnim.frameBytes());
      rxMask |= 1UL << i;
      return ST_OK;
    }
    case AO_END: {
      if (!rxActive) return ST_BAD_PAYLOAD;
      uint32_t all = rxAnim.frames >= 32 ? 0xFFFFFFFFUL : (1UL << rxAnim.frames) - 1;
      if (rxMask != all) return ST_ERROR;          // ada bingkai yang belum diterima
      rxActive = false;
      Serial.printf("[img] animasi %u bingkai %ux%u -> %s%u\r\n", rxAnim.frames, rxAnim.w, rxAnim.h,
                    rxSlot ? "slot " : "tampil ", rxSlot);
      if (rxSlot == 0) {
        imgstore::current().swap(rxAnim);
        rxAnim.release();
        events::post(EV_BITMAP);
        return ST_OK;
      }
      bool ok = imgstore::save(rxSlot, rxAnim);
      rxAnim.release();
      if (!ok) return ST_ERROR;
      toastSlot(rxSlot, false);
      return ST_OK;
    }
    case AO_ABORT:
      rxActive = false;
      rxAnim.release();
      return ST_OK;
    case AO_READ: {
      uint8_t slot = r.u8();
      bool firstOnly = r.has() && r.u8();
      if (!r.ok() || slot < 1 || slot > imgstore::SLOTS) return ST_BAD_PAYLOAD;
      out.a.release();
      if (!imgstore::load(slot, out.a, firstOnly)) return ST_ERROR;
      out.active = true; out.t = t; out.slot = slot; out.next = -1; out.at = millis() + 20;
      return ST_OK;
    }
    case AO_LIST:
      afterAck = sendList;
      return ST_OK;
    case AO_DELETE: {
      uint8_t slot = r.u8();
      if (!r.ok() || slot < 1 || slot > imgstore::SLOTS) return ST_BAD_PAYLOAD;
      if (!imgstore::remove(slot)) return ST_ERROR;
      toastSlot(slot, true);
      return ST_OK;
    }
    case AO_SHOW: {
      uint8_t slot = r.u8();
      uint16_t dur = r.has() ? r.u16() : 0;
      if (!r.ok() || slot < 1 || slot > imgstore::SLOTS) return ST_BAD_PAYLOAD;
      Anim a;
      if (!imgstore::load(slot, a)) return ST_ERROR;
      a.durationS = dur;
      imgstore::current().swap(a);
      events::post(EV_BITMAP);
      return ST_OK;
    }
    case AO_LIST_REPORT: return ST_BAD_PAYLOAD;   // hanya D->H
    default: return ST_NOT_SUPPORTED;
  }
}

// Satu bagian galeri per panggilan: BEGIN, FRAME..., END
static void pumpOutbox(uint32_t now) {
  if (!out.active || (int32_t)(now - out.at) < 0) return;
  Anim& a = out.a;
  static uint8_t p[2 + Anim::MAX_BYTES / 16];     // cukup untuk 1 bingkai layar penuh (1024 B)
  Writer w(p, sizeof(p));
  if (out.next < 0) {
    w.u8(AO_BEGIN); w.u8(out.slot); w.u8(a.frames); w.u16(a.frameMs); w.u8(a.loops); w.u16(0);
    w.u16((uint16_t)a.x); w.u16((uint16_t)a.y); w.u8(a.w); w.u8(a.h);
  } else if (out.next < a.frames) {
    w.u8(AO_FRAME); w.u8((uint8_t)out.next); w.bytes(a.frame(out.next), a.frameBytes());
  } else {
    w.u8(AO_END);
    out.active = false;
  }
  lklink::send(out.t, T_ANIM, 0, p, w.len());
  out.next++;
  out.at = now + (out.t == TR_BLE ? 40 : 5);
  if (!out.active) a.release();
}

enum ScreenOp : uint8_t { SC_START = 0, SC_STOP = 1, SC_FRAME = 2, SC_INPUT = 3, SC_CAPTURE = 4 };

static uint8_t onScreen(Transport t, Reader& r) {
  uint8_t op = r.u8();
  if (!r.ok()) return ST_BAD_PAYLOAD;
  switch (op) {
    case SC_START: {
      uint8_t fps = r.has() ? r.u8() : 0;
      if (!session[t]) return ST_NOT_ALLOWED;     // butuh HELLO dulu
      if (fps == 0) fps = 10;
      if (fps > 15) fps = 15;
      bool fresh = !mirror[t].until;
      mirror[t].until = millis() + MIRROR_TIMEOUT_MS;
      mirror[t].intervalMs = 1000 / fps;
      if (fresh) { mirror[t].lastCrc = 0; mirror[t].capture = true; }
      return ST_OK;
    }
    case SC_STOP: mirror[t] = Mirror(); return ST_OK;
    case SC_CAPTURE:
      if (!session[t]) return ST_NOT_ALLOWED;
      mirror[t].capture = true;
      return ST_OK;
    case SC_INPUT: {
      uint8_t g = r.u8();
      if (!r.ok() || g < 1 || g > 4) return ST_BAD_PAYLOAD;
      core::injectGesture((Gesture)g);            // G_TAP..G_LONG = 1..4, sama dengan tombol fisik
      return ST_OK;
    }
    case SC_FRAME: return ST_BAD_PAYLOAD;         // hanya D->H
    default: return ST_NOT_SUPPORTED;
  }
}

// Kirim isi layar ke host yang sedang mirror: hanya jika berubah, maks fps, + keepalive 2 dtk
static void pumpMirror(uint32_t now) {
  static uint8_t f[4 + ((SCREEN_W + 7) / 8) * SCREEN_H];   // op, flags, w, h, data
  bool snapped = false;
  uint16_t n = 0, crc = 0;
  for (uint8_t t = 0; t < TR_COUNT; t++) {
    Mirror& m = mirror[t];
    bool active = m.until && (int32_t)(m.until - now) > 0;
    if (m.until && !active) m = Mirror();         // 30 dtk tanpa START: berhenti
    if (!active && !m.capture) continue;
    if (!m.capture && (int32_t)(now - m.lastCheck) < (int32_t)m.intervalMs) continue;
    m.lastCheck = now;
    if (!snapped) {                               // satu snapshot untuk semua host
      n = display::snapshot(f + 4);
      f[0] = SC_FRAME; f[1] = core::screenOn() ? 1 : 0; f[2] = SCREEN_W; f[3] = SCREEN_H;
      crc = crc16(f + 1, n + 3);
      snapped = true;
    }
    bool due = m.capture || crc != m.lastCrc || (int32_t)(now - m.lastSent) > (int32_t)MIRROR_KEEPALIVE_MS;
    if (!due) continue;
    lklink::send((Transport)t, T_SCREEN, 0, f, 4 + n);
    m.lastCrc = crc;
    m.lastSent = now;
    m.capture = false;
  }
}

static uint8_t onUnpair(Transport t) {
  if (t != TR_BLE) return ST_NOT_ALLOWED;         // lewat USB: perintah console 'forget'
  unpairAt = millis() + 300;                      // beri waktu ACK terkirim
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
      case T_NOTIF:       st = onNotif(r); break;
      case T_CALL:        st = onCall(r); break;
      case T_EXPRESSION:  st = onExpression(r); break;
      case T_DICE:        st = onDice(r); break;
      case T_GOTO:        st = onGoto(r); break;
      case T_FIND_KEYS:   st = onFindKeys(r); break;
      case T_FIND_PHONE:  st = onFindPhone(r); break;
      case T_CUSTOM_TEXT: st = onCustomText(r); break;
      case T_BITMAP:      st = onBitmap(r); break;
      case T_ANIM:        st = onAnim(t, r); break;
      case T_UNPAIR:      st = onUnpair(t); break;
      case T_SCREEN:      st = onScreen(t, r); break;
      case T_TEXT_SLOT:   st = onTextSlot(t, r); break;
      // Dikenal, tapi belum ada di firmware ini / arahnya hanya D->H
      case T_DEVICE_INFO: case T_OTA: case T_BUTTON:
      case T_NAV: case T_PC_STATS: case T_MEETING: case T_PHONE_STATS:
      case T_WIFI_PROV: case T_WIFI_STATUS:
        st = ST_NOT_SUPPORTED; break;
      default: st = ST_UNKNOWN_TYPE; break;
    }
  }
  if ((type != T_HELLO && type != T_ANIM && type != T_SCREEN) || st != ST_OK)
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

void reportFindKeys(bool on, uint8_t seconds) {
  uint8_t p[2] = {(uint8_t)(on ? 1 : 0), seconds};
  broadcast(T_FIND_KEYS, p, sizeof(p));
}

void consoleActivity() {
  if (session[TR_USB]) Serial.println("[link] usb: console dipakai, pesan tanpa diminta dihentikan sampai HELLO");
  endSession(TR_USB);
}

void begin() {
  refreshName();
  imgstore::begin();
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
  if (blePrevSecure && !sec) {                    // HP putus: sesi & button_events selesai
    uint16_t reason; int8_t r; uint32_t age;
    if (link_ble::takeLoss(reason, r, age) && session[TR_BLE]) {
      bool far = r != 0 && age <= LEAVE_RSSI_MAX_AGE_MS && r < LEAVE_RSSI_NEAR;
      bool arm = settings::get().leaveAlert && reason == REASON_TIMEOUT && far;
      Serial.printf("[link] HP hilang: alasan 0x%03X, RSSI %d dBm (%lu ms lalu) -> %s\r\n", reason, r,
                    (unsigned long)(age == UINT32_MAX ? 0 : age), arm ? "pengingat 20 dtk" : "tanpa pengingat");
      if (arm) { leaveAt = now + LEAVE_GRACE_MS; if (!leaveAt) leaveAt = 1; }
    }
    endSession(TR_BLE);
    if (out.active && out.t == TR_BLE) { out.active = false; out.a.release(); }
    if (textOut.active && textOut.t == TR_BLE) textOut.active = false;
  }
  if (sec && !blePrevSecure) {                    // HP tersambung lagi: batalkan / tutup pengingat
    leaveAt = 0;
    if (leaveShown) { leaveShown = false; events::post(EV_LEFT, 0); }
  }
  if (leaveAt && !sec && (int32_t)(now - leaveAt) >= 0) {
    leaveAt = 0;
    leaveShown = true;
    Serial.println("[link] HP tertinggal: pengingat");
    events::post(EV_LEFT, 1);
  }
  blePrevSecure = sec;
  if (unpairAt && (int32_t)(now - unpairAt) >= 0) {
    unpairAt = 0;
    link_ble::unpairCurrent();
    events::post(EV_TOAST, 0, "HP dilupakan");
  }
#endif
  pumpOutbox(now);
  pumpTextOut(now);
  pumpMirror(now);
}

const char* deviceName() { return devName; }

void displayName(char* out, size_t cap) { toOledText(devName, out, cap); }

void rename(const char* utf8) {
  Settings& s = settings::get();
  if (utf8 != s.name) sanitizeUtf8((const uint8_t*)utf8, strlen(utf8), s.name, sizeof(s.name) - 1);
  settings::save();
  refreshName();
#ifndef WOKWI_SIM
  link_ble::setName(devName);                     // nama iklan BLE ikut berubah
#endif
  Serial.printf("[link] nama Bluetooth: %s\r\n", devName);
}

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
  char shown[32];
  displayName(shown, sizeof(shown));
  Serial.printf("  nama %s (OLED: %s) | BLE %s | bond %u | MTU %u | sesi usb=%u ble=%u | tombol usb=%u ble=%u | frame masuk %lu keluar %lu\r\n",
                devName, shown, bleStatus(), bondCount(),
#ifdef WOKWI_SIM
                0,
#else
                link_ble::mtu(),
#endif
                session[TR_USB], session[TR_BLE], btnEvents[TR_USB], btnEvents[TR_BLE], rxFrames, txFrames);
}

}  // namespace lklink
