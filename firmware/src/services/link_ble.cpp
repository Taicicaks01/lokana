#include "link_internal.h"
#include "link_proto.h"
#include "core/events.h"
#include "drivers/buzzer.h"

#ifndef WOKWI_SIM
#include <NimBLEDevice.h>
#include <freertos/stream_buffer.h>
#include <esp_random.h>

// ============================================================
//  BLE: satu service Lokana Link, RX (write) + TX (notify).
//  Keamanan: pairing passkey 6 digit di OLED (DisplayOnly), bonding, Secure Connections.
//  RX mewajibkan enkripsi + autentikasi; TX hanya dikirim ke koneksi yang sudah aman.
//  Callback NimBLE berjalan di task NimBLE -> data & status dititipkan, diproses di loop.
// ============================================================

static const char* SVC_UUID = "6c6f6b61-0000-4c4b-8000-6c6f6b616e61";
static const char* RX_UUID  = "6c6f6b61-0001-4c4b-8000-6c6f6b616e61";
static const char* TX_UUID  = "6c6f6b61-0002-4c4b-8000-6c6f6b616e61";

static NimBLEServer* server = nullptr;
static NimBLECharacteristic* txChar = nullptr;
static StreamBufferHandle_t rxBuf = nullptr;
static lk::FrameParser parser;

// Ditulis task NimBLE, dibaca loop
static volatile bool isConn = false, isSecure = false;
static volatile uint16_t connHandle = 0xFFFF, peerMtu = 23;
static volatile uint32_t passkey = 0;
static volatile bool passkeyNew = false;       // passkey baru untuk ditampilkan
static volatile int8_t authResult = -1;         // -1 belum ada, 0 gagal, 1 berhasil
static volatile bool dropped = false, disconnected = false;
static volatile bool lostSecure = false;        // koneksi yang baru putus sudah aman
static volatile uint16_t lostReason = 0;        // alasan putus dari event GAP
// RSSI koneksi aman, diukur di loop tiap 2 detik (pengingat ketinggalan)
static int8_t rssi = 0;
static uint32_t rssiAt = 0;
static bool lossReady = false;
static uint16_t lossReason = 0;
static int8_t lossRssi = 0;
static uint32_t lossAge = 0;

static volatile bool connUpdated = false;        // HP menyetujui / mengubah parameter koneksi

// Callback server NimBLE 1.4 tidak memberi alasan putus: ambil dari event GAP mentah.
static int gapEvent(struct ble_gap_event* e, void*) {
  if (e->type == BLE_GAP_EVENT_DISCONNECT) lostReason = e->disconnect.reason;
  if (e->type == BLE_GAP_EVENT_CONN_UPDATE && e->conn_update.status == 0) connUpdated = true;
  return 0;
}

// ---------------- Hemat daya (0.5.7) ----------------
// Iklan: cepat 100-150 ms selama 60 dtk setelah boot/putus atau selama layar menyala, lalu hemat 1-1,1 dtk.
// Koneksi (diminta Lokana, HP yang memutuskan): aktif 15-30 ms; layar mati 100-150 ms + slave latency 3
// (Lokana boleh melewatkan event tanpa data, bangun ±0,6 dtk). Supervision timeout 4 dtk untuk keduanya.
// RSSI pengingat ketinggalan tetap dibaca tiap 2 dtk.
static const uint16_t ADV_FAST_MIN = 160, ADV_FAST_MAX = 240;    // satuan 0,625 ms
static const uint16_t ADV_SLOW_MIN = 1600, ADV_SLOW_MAX = 1760;
static const uint32_t ADV_FAST_MS = 60000;
static bool wantActive = true, advFast = true;
static uint32_t advFastUntil = ADV_FAST_MS, secureSince = 0;
static int8_t connMode = -1;                     // -1 belum diminta, 0 hemat, 1 aktif

static void setAdv(bool fast) {
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->setMinInterval(fast ? ADV_FAST_MIN : ADV_SLOW_MIN);
  adv->setMaxInterval(fast ? ADV_FAST_MAX : ADV_SLOW_MAX);
  advFast = fast;
  if (adv->isAdvertising()) { adv->stop(); adv->start(); }
  Serial.printf("[ble] iklan %s\r\n", fast ? "cepat (100-150 ms)" : "hemat (1-1,1 dtk)");
}

static void requestConn(bool active) {
  if (active) server->updateConnParams(connHandle, 12, 24, 0, 400);   // 15-30 ms, latency 0, 4 dtk
  else server->updateConnParams(connHandle, 80, 120, 3, 400);         // 100-150 ms, latency 3, 4 dtk
  connMode = active ? 1 : 0;
}
static bool showingKey = false;                 // hanya dipakai di loop

// Data iklan: nama di paket utama, UUID 128-bit di scan response (tidak muat bersama).
// Nama UTF-8 maks 26 byte = 31 - 3 (flags) - 2 (header nama).
static void applyAdvertising(const char* name) {
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  NimBLEAdvertisementData ad, sr;
  ad.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
  ad.setName(name);
  sr.setCompleteServices(NimBLEUUID(SVC_UUID));
  adv->setAdvertisementData(ad);
  adv->setScanResponseData(sr);
}

class ServerCb : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* s, ble_gap_conn_desc* d) override {
    connHandle = d->conn_handle;
    isConn = true; isSecure = false; peerMtu = 23;
    NimBLEDevice::startSecurity(d->conn_handle);  // minta pairing / enkripsi ulang (sudah bonded)
  }
  void onDisconnect(NimBLEServer* s, ble_gap_conn_desc* d) override {
    lostSecure = isSecure;
    isConn = false; isSecure = false; connHandle = 0xFFFF;
    disconnected = true;                          // iklan dimulai ulang otomatis oleh NimBLE
  }
  void onMTUChange(uint16_t mtu, ble_gap_conn_desc* d) override { peerMtu = mtu; }
  uint32_t onPassKeyRequest() override {
    uint32_t k = esp_random() % 1000000UL;
    passkey = k;
    passkeyNew = true;
    return k;
  }
  void onAuthenticationComplete(ble_gap_conn_desc* d) override {
    bool ok = d->sec_state.encrypted && d->sec_state.authenticated;
    isSecure = ok;
    authResult = ok ? 1 : 0;
    if (!ok) NimBLEDevice::getServer()->disconnect(d->conn_handle);
  }
};

class RxCb : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c, ble_gap_conn_desc* d) override {
    NimBLEAttValue v = c->getValue();
    if (xStreamBufferSend(rxBuf, v.data(), v.size(), 0) != v.size()) dropped = true;
  }
};

static ServerCb serverCb;
static RxCb rxCb;

namespace link_ble {

void begin(const char* name) {
  rxBuf = xStreamBufferCreate(4096, 1);
  NimBLEDevice::init(name);
  NimBLEDevice::setMTU(247);
  NimBLEDevice::setSecurityAuth(true, true, true);           // bonding, MITM, Secure Connections
  NimBLEDevice::setSecurityIOCap(BLE_HS_IO_DISPLAY_ONLY);   // passkey tampil di OLED

  NimBLEDevice::setCustomGapHandler(gapEvent);
  server = NimBLEDevice::createServer();
  server->setCallbacks(&serverCb, false);
  NimBLEService* svc = server->createService(SVC_UUID);
  NimBLECharacteristic* rx = svc->createCharacteristic(
      RX_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR |
               NIMBLE_PROPERTY::WRITE_ENC | NIMBLE_PROPERTY::WRITE_AUTHEN, 512);
  rx->setCallbacks(&rxCb);
  txChar = svc->createCharacteristic(TX_UUID, NIMBLE_PROPERTY::NOTIFY);
  svc->start();

  applyAdvertising(name);
  NimBLEDevice::getAdvertising()->setMinInterval(ADV_FAST_MIN);
  NimBLEDevice::getAdvertising()->setMaxInterval(ADV_FAST_MAX);
  NimBLEDevice::getAdvertising()->start();
  Serial.printf("[ble] iklan sebagai \"%s\" (bond tersimpan: %d)\r\n", name, NimBLEDevice::getNumBonds());
}

void update(uint32_t now) {
  // Status dari task NimBLE -> event untuk modul
  if (passkeyNew) {
    passkeyNew = false;
    showingKey = true;
    Serial.println("[ble] pairing: kode tampil di layar");   // kode tidak ditulis ke log
    events::post(EV_PAIR_CODE, (int32_t)passkey);
  }
  int8_t a = authResult;
  if (a >= 0) {
    authResult = -1;
    Serial.printf("[ble] autentikasi %s\r\n", a ? "berhasil" : "GAGAL");
    if (showingKey) { showingKey = false; events::post(EV_PAIR_DONE, a); }
    else if (a) events::post(EV_TOAST, 0, "HP tersambung");
    else events::post(EV_TOAST, 0, "Pairing lama: ulangi di HP");   // HP masih memegang bond lama
  }
  if (disconnected) {
    disconnected = false;
    parser.reset();
    xStreamBufferReset(rxBuf);
    Serial.printf("[ble] terputus (alasan 0x%03X)\r\n", lostReason);
    if (lostSecure) {
      lossReady = true;
      lossReason = lostReason;
      lossRssi = rssiAt ? rssi : 0;
      lossAge = rssiAt ? now - rssiAt : UINT32_MAX;
    }
    lostSecure = false;
    rssiAt = 0;
    secureSince = 0;
    connMode = -1;
    advFastUntil = now + ADV_FAST_MS;             // cepat tersambung lagi
    if (!advFast) setAdv(true);
    if (showingKey) { showingKey = false; events::post(EV_PAIR_DONE, 0); }
  }
  if (dropped) { dropped = false; Serial.println("[ble] buffer RX penuh, data dibuang"); }

  // Hemat daya: iklan & parameter koneksi
  if (!isConn) {
    if (wantActive) {                             // layar menyala: mungkin sedang mau menyambungkan HP
      advFastUntil = now + 30000;
      if (!advFast) setAdv(true);
    } else if (advFast && (int32_t)(now - advFastUntil) >= 0) setAdv(false);
  } else if (isSecure) {
    if (!secureSince) secureSince = now ? now : 1;
    // Tunggu 3 dtk setelah aman (HP masih menukar MTU / discovery dengan interval cepat)
    if ((int32_t)(now - secureSince) > 3000 && connMode != (wantActive ? 1 : 0)) requestConn(wantActive);
  }
  if (connUpdated) {
    connUpdated = false;
    ble_gap_conn_desc d;
    if (isConn && ble_gap_conn_find(connHandle, &d) == 0)
      Serial.printf("[ble] koneksi: interval %u ms, latency %u, timeout %u ms\r\n", d.conn_itvl * 5 / 4,
                    d.conn_latency, d.supervision_timeout * 10);
  }
  if (isConn && isSecure && (int32_t)(now - rssiAt) >= 2000) {
    int8_t r;
    if (ble_gap_conn_rssi(connHandle, &r) == 0 && r != 127) { rssi = r; rssiAt = now ? now : 1; }
    else rssiAt = now ? now : 1;                  // coba lagi 2 detik lagi (tanpa mengubah nilai terakhir)
  }

  // Aliran byte RX -> frame
  if (parser.stale(now)) parser.reset();
  uint8_t buf[128];
  size_t n;
  int budget = 16;
  while (budget-- && (n = xStreamBufferReceive(rxBuf, buf, sizeof(buf), 0)) > 0) {
    for (size_t i = 0; i < n; i++)
      if (parser.feed(buf[i], now))
        lklink::dispatch(lklink::TR_BLE, parser.type(), parser.seq(), parser.payload(), parser.len(), parser.tooBig());
  }
}

bool write(const uint8_t* frame, uint16_t n) {
  if (!isConn || !isSecure || !txChar) return false;
  uint16_t chunk = peerMtu > 3 ? peerMtu - 3 : 20;
  for (uint16_t i = 0; i < n; i += chunk) {
    uint16_t m = (n - i < chunk) ? n - i : chunk;
    txChar->notify(frame + i, m);
  }
  return true;
}

void setActive(bool active) { wantActive = active; }

void printPower() {
  ble_gap_conn_desc d;
  if (isConn && ble_gap_conn_find(connHandle, &d) == 0)
    Serial.printf("  koneksi: interval %u ms, latency %u, timeout %u ms (diminta: %s)\r\n", d.conn_itvl * 5 / 4,
                  d.conn_latency, d.supervision_timeout * 10, connMode == 1 ? "aktif" : connMode == 0 ? "hemat" : "-");
  else Serial.printf("  iklan: %s\r\n", advFast ? "cepat (100-150 ms)" : "hemat (1-1,1 dtk)");
}

bool connected() { return isConn; }
bool secure() { return isConn && isSecure; }
bool pairing() { return showingKey; }
uint8_t bonds() { return (uint8_t)NimBLEDevice::getNumBonds(); }
uint16_t mtu() { return peerMtu; }

bool takeLoss(uint16_t& reason, int8_t& r, uint32_t& age) {
  if (!lossReady) return false;
  lossReady = false;
  reason = lossReason; r = lossRssi; age = lossAge;
  return true;
}

void forget() {
  if (isConn) server->disconnect(connHandle);
  NimBLEDevice::deleteAllBonds();
}

void unpairCurrent() {
  if (!isConn) return;
  NimBLEAddress peer = server->getPeerIDInfo(connHandle).getIdAddress();
  server->disconnect(connHandle);
  bool ok = NimBLEDevice::deleteBond(peer);
  Serial.printf("[ble] bond HP %s dihapus: %s\r\n", peer.toString().c_str(), ok ? "ya" : "tidak ada");
}

void setName(const char* name) {
  NimBLEDevice::setDeviceName(name);              // nama GAP (dibaca HP saat tersambung)
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  bool was = adv->isAdvertising();
  if (was) adv->stop();
  applyAdvertising(name);
  if (was || !isConn) adv->start();
  Serial.printf("[ble] nama iklan: %s\r\n", name);
}

}  // namespace link_ble

#else  // WOKWI_SIM: Wokwi tidak mendukung BLE

namespace link_ble {
void begin(const char*) {}
void update(uint32_t) {}
bool write(const uint8_t*, uint16_t) { return false; }
bool connected() { return false; }
bool secure() { return false; }
bool pairing() { return false; }
uint8_t bonds() { return 0; }
void forget() {}
void unpairCurrent() {}
void setName(const char*) {}
uint16_t mtu() { return 0; }
bool takeLoss(uint16_t&, int8_t&, uint32_t&) { return false; }
void setActive(bool) {}
void printPower() {}
}

#endif
