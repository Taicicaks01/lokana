#pragma once
#include <Arduino.h>

// Pembaruan firmware lewat Lokana Link (pesan OTA, LOKANA_LINK.md §OTA) + masa uji & rollback.
// Layanan link memanggil begin/chunk/end/hostAbort lalu mengirim PROGRESS/ABORT dari takeProgress/takeAbort.
// Status yang dikembalikan = kode status ACK Lokana Link (lk::ST_*).
namespace ota {
enum Reason : uint8_t {
  R_NONE = 0, R_HASH = 1, R_WRITE = 2, R_TIMEOUT = 3, R_SIZE = 4, R_HOST = 5, R_IMAGE = 6,
};

uint8_t begin(uint8_t transport, uint32_t size, const uint8_t sha256[32], const char* version);
uint8_t chunk(uint8_t transport, uint32_t offset, const uint8_t* data, uint16_t n);
uint8_t end(uint8_t transport);              // OK = image dipasang, restart dijadwalkan
void hostAbort(uint8_t transport);           // host membatalkan (ABORT dari host)
void transportLost(uint8_t transport);       // koneksi putus di tengah OTA

bool active();                               // sedang menerima image
bool installing();                           // image diterima, menunggu restart
uint8_t transport();
uint32_t received();
uint32_t total();
const char* version();

bool takeProgress(uint32_t& received);       // PROGRESS perlu dikirim ke host (tiap 64 KB / selesai)
uint8_t takeAbort();                         // alasan ABORT yang perlu dilaporkan (0 = tidak ada)

// Masa uji firmware baru: dipanggil di setup() setelah OLED dicoba, lalu tiap loop.
void bootCheck(bool oledOk);
void update(uint32_t now);
bool pendingVerify();                        // firmware ini belum ditandai valid
const char* rolledBackFrom();                // versi yang baru saja ditolak ("" = tidak ada)
void printStatus();                          // console `ota`
}
