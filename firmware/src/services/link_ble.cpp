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
    Serial.println("[ble] terputus");
    if (showingKey) { showingKey = false; events::post(EV_PAIR_DONE, 0); }
  }
  if (dropped) { dropped = false; Serial.println("[ble] buffer RX penuh, data dibuang"); }

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

bool connected() { return isConn; }
bool secure() { return isConn && isSecure; }
bool pairing() { return showingKey; }
uint8_t bonds() { return (uint8_t)NimBLEDevice::getNumBonds(); }
uint16_t mtu() { return peerMtu; }

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
}

#endif
