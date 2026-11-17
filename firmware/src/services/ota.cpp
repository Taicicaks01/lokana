#include "ota.h"
#include <esp_ota_ops.h>
#include <esp_system.h>
#include <mbedtls/sha256.h>
#include "link_proto.h"
#include "core/events.h"
#include "drivers/display.h"
#include "config.h"
#include <Preferences.h>

// Penanda versi Lokana OS di dalam image (versi di header esp_app_desc_t = versi ESP-IDF, bukan Lokana).
// Alat PC & aplikasi mencari "LOKANA_OS_VERSION:" di file .bin untuk tahu versinya sebelum OTA.
extern "C" __attribute__((used)) const char LOKANA_VERSION_TAG[] = "LOKANA_OS_VERSION:" FW_VERSION;

// Versi yang sedang dicoba lewat OTA disimpan di NVS sampai ditandai valid; kalau saat boot masih ada
// tapi bukan versi yang berjalan, berarti bootloader sudah kembali ke versi lama (rollback).
static void setTrying(const char* v) {
  Preferences p;
  p.begin("ota", false);
  if (v) p.putString("try", v); else p.remove("try");
  p.end();
}

// Arduino menandai firmware valid sebelum setup() (esp32-hal-misc.c). Ditimpa: Lokana sendiri yang menandai
// valid setelah boot terbukti sehat (lihat update()), jadi crash/macet di setup() atau loop() tetap rollback.
extern "C" bool verifyRollbackLater() { return true; }

using namespace lk;

static const uint32_t TIMEOUT_MS = 30000;        // tanpa CHUNK selama ini = batal
static const uint32_t VERIFY_MS = 10000;         // masa uji sebelum ditandai valid
static const uint32_t PROGRESS_STEP = 65536;

static esp_ota_handle_t handle = 0;
static const esp_partition_t* target = nullptr;
static mbedtls_sha256_context sha;
static uint8_t want[32];
static char ver[32] = "";
static bool act = false, done = false;
static uint8_t tr = 0;
static uint32_t size = 0, got = 0, lastAt = 0, restartAt = 0;
static bool progressDue = false;
static uint8_t abortDue = ota::R_NONE;

static bool verifying = false;
static uint32_t verifyFrom = 0;
static char rolled[32] = "";

static void cleanup() {
  if (handle) { esp_ota_abort(handle); handle = 0; }
  if (act) mbedtls_sha256_free(&sha);
  act = false;
}

static void fail(uint8_t reason, bool report = true) {
  Serial.printf("[ota] gagal (alasan %u) di %lu/%lu byte\r\n", reason, (unsigned long)got, (unsigned long)size);
  cleanup();
  if (report) abortDue = reason;
  events::post(EV_OTA, -(int32_t)reason);
}

namespace ota {

uint8_t begin(uint8_t t, uint32_t n, const uint8_t sha256[32], const char* version) {
  if (done) return ST_BUSY;                       // image sudah dipasang, sebentar lagi restart
  if (act && t != tr) return ST_BUSY;
  if (act) cleanup();                             // BEGIN baru dari host yang sama = mulai ulang
  target = esp_ota_get_next_update_partition(nullptr);
  if (!target) return ST_ERROR;
  if (!n || n > target->size) return ST_BAD_PAYLOAD;
  if (esp_ota_begin(target, OTA_WITH_SEQUENTIAL_WRITES, &handle) != ESP_OK) { handle = 0; return ST_ERROR; }
  mbedtls_sha256_init(&sha);
  mbedtls_sha256_starts(&sha, 0);
  memcpy(want, sha256, 32);
  strlcpy(ver, version, sizeof(ver));
  act = true; tr = t; size = n; got = 0; lastAt = millis();
  progressDue = false; abortDue = R_NONE;
  Serial.printf("[ota] mulai: v%s, %lu byte -> %s\r\n", ver, (unsigned long)n, target->label);
  events::post(EV_OTA, 1);
  return ST_OK;
}

uint8_t chunk(uint8_t t, uint32_t off, const uint8_t* d, uint16_t n) {
  if (!act || t != tr || !n) return ST_BAD_PAYLOAD;
  if (off < got && off + n == got) return ST_OK;  // kiriman ulang (ACK sebelumnya hilang)
  if (off != got || got + n > size) return ST_BAD_PAYLOAD;
  esp_err_t e = esp_ota_write(handle, d, n);
  // CHUNK pertama yang bukan image ESP32 (byte awal != 0xE9) langsung ditolak di sini
  if (e == ESP_ERR_OTA_VALIDATE_FAILED) { fail(R_IMAGE); return ST_ERROR; }
  if (e != ESP_OK) { fail(R_WRITE); return ST_ERROR; }
  mbedtls_sha256_update(&sha, d, n);
  uint32_t before = got;
  got += n;
  lastAt = millis();
  if (got / PROGRESS_STEP != before / PROGRESS_STEP || got == size) progressDue = true;
  return ST_OK;
}

uint8_t end(uint8_t t) {
  if (!act || t != tr || got != size) return ST_BAD_PAYLOAD;
  uint8_t out[32];
  mbedtls_sha256_finish(&sha, out);
  if (memcmp(out, want, 32)) { fail(R_HASH); return ST_ERROR; }
  esp_err_t e = esp_ota_end(handle);              // memeriksa header & isi image ESP32-C3
  handle = 0;
  if (e != ESP_OK) { Serial.printf("[ota] image ditolak: %s\r\n", esp_err_to_name(e)); fail(R_IMAGE); return ST_ERROR; }
  if (esp_ota_set_boot_partition(target) != ESP_OK) { fail(R_IMAGE); return ST_ERROR; }
  mbedtls_sha256_free(&sha);
  act = false;
  done = true;
  setTrying(ver);
  restartAt = millis() + 700;                     // beri waktu ACK terkirim
  if (!restartAt) restartAt = 1;
  Serial.printf("[ota] v%s terpasang di %s, restart...\r\n", ver, target->label);
  events::post(EV_OTA, 2);
  return ST_OK;
}

void hostAbort(uint8_t t) {
  if (!act || t != tr) return;
  fail(R_HOST, false);
}

void transportLost(uint8_t t) {
  if (act && t == tr) fail(R_TIMEOUT, false);
}

bool active() { return act; }
bool installing() { return done; }
uint8_t transport() { return tr; }
uint32_t received() { return got; }
uint32_t total() { return size; }
const char* version() { return ver; }

bool takeProgress(uint32_t& r) {
  if (!progressDue) return false;
  progressDue = false;
  r = got;
  return true;
}

uint8_t takeAbort() {
  uint8_t r = abortDue;
  abortDue = R_NONE;
  return r;
}

void bootCheck(bool oledOk) {
  const esp_partition_t* run = esp_ota_get_running_partition();
  esp_ota_img_states_t st;
  if (esp_ota_get_state_partition(run, &st) == ESP_OK && st == ESP_OTA_IMG_PENDING_VERIFY) {
    Serial.printf("[ota] firmware baru (%s) dalam masa uji %lu dtk\r\n", run->label, (unsigned long)VERIFY_MS / 1000);
    if (!oledOk) {
      Serial.println("[ota] OLED tidak menjawab -> kembali ke firmware lama");
      Serial.flush();
      esp_ota_mark_app_invalid_rollback_and_reboot();
    }
    verifying = true;
    verifyFrom = millis();
    enableLoopWDT();                              // macet > 5 dtk = panic -> bootloader rollback
  }
  // Baru saja kembali dari firmware yang gagal?
  if (!verifying) {
    Preferences p;
    p.begin("ota", true);
    String tried = p.getString("try", "");
    p.end();
    if (tried.length()) {
      setTrying(nullptr);
      if (tried != FW_VERSION) {
        strlcpy(rolled, tried.c_str(), sizeof(rolled));
        Serial.printf("[ota] firmware v%s gagal boot, kembali ke v" FW_VERSION "\r\n", rolled);
        events::post(EV_OTA, -100);               // modul Update menampilkan pemberitahuan rollback
      }
    }
  }
}

void update(uint32_t now) {
  if (act && (int32_t)(now - lastAt) > (int32_t)TIMEOUT_MS) fail(R_TIMEOUT);
  if (restartAt && (int32_t)(now - restartAt) >= 0) {
    Serial.flush();
    esp_restart();
  }
  if (verifying && (int32_t)(now - verifyFrom) >= (int32_t)VERIFY_MS && display::present()) {
    esp_ota_mark_app_valid_cancel_rollback();
    setTrying(nullptr);
    disableLoopWDT();
    verifying = false;
    Serial.println("[ota] firmware sehat, ditandai valid");
    events::post(EV_OTA, 3);
  }
}

bool pendingVerify() { return verifying; }

void printStatus() {
  const esp_partition_t* run = esp_ota_get_running_partition();
  esp_ota_img_states_t st = ESP_OTA_IMG_UNDEFINED;
  esp_ota_get_state_partition(run, &st);
  const char* stName = st == ESP_OTA_IMG_VALID ? "valid" : st == ESP_OTA_IMG_PENDING_VERIFY ? "masa uji" :
                       st == ESP_OTA_IMG_UNDEFINED ? "upload USB" : "lain";
  Serial.printf("ota: berjalan di %s (%s), v%s\r\n", run->label, stName, LOKANA_VERSION_TAG + 18);
  if (act) Serial.printf("ota: menerima v%s %lu/%lu byte\r\n", ver, (unsigned long)got, (unsigned long)size);
  if (rolled[0]) Serial.printf("ota: v%s ditolak, kembali ke versi ini\r\n", rolled);
}

const char* rolledBackFrom() { return rolled; }

}  // namespace ota
