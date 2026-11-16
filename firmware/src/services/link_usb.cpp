#include "link_internal.h"
#include "link_proto.h"
#include "console.h"

// USB serial dipakai bersama: teks console + frame biner dalam envelope
//   A5 5A [frame] [CRC-16/CCITT-FALSE u16 LE atas frame]
// 0xA5 tidak pernah muncul di teks ASCII, jadi byte itu menandai awal envelope.

using namespace lk;

enum UsbState : uint8_t { U_TEXT, U_SYNC, U_FRAME, U_CRC0, U_CRC1 };
static UsbState st = U_TEXT;
static FrameParser parser;
static uint16_t crc = 0xFFFF, crcRx = 0;
static uint32_t lastByte = 0, crcErrors = 0;

static void toText() { st = U_TEXT; parser.reset(); }

static void feed(uint8_t b, uint32_t now) {
  switch (st) {
    case U_TEXT:
      if (b == ENV0) st = U_SYNC;
      else console::feed((char)b);
      break;
    case U_SYNC:
      if (b == ENV1) { st = U_FRAME; crc = 0xFFFF; parser.reset(); }
      else { st = U_TEXT; feed(b, now); }          // bukan envelope: proses ulang sebagai teks
      break;
    case U_FRAME:
      crc = crc16(crc, b);
      if (parser.feed(b, now)) st = U_CRC0;
      break;
    case U_CRC0:
      crcRx = b; st = U_CRC1;
      break;
    case U_CRC1:
      crcRx |= (uint16_t)b << 8;
      st = U_TEXT;
      if (crcRx != crc) {                            // CRC salah: buang tanpa balasan (host kirim ulang)
        crcErrors++;
        Serial.printf("[link] usb: CRC salah (%04X != %04X), frame dibuang\r\n", crcRx, crc);
        break;
      }
      lklink::dispatch(lklink::TR_USB, parser.type(), parser.seq(), parser.payload(), parser.len(), parser.tooBig());
      break;
  }
}

namespace link_usb {

void begin() {}

void update(uint32_t now) {
  // Envelope terputus lebih dari 1 detik -> kembali ke mode teks
  if (st != U_TEXT && (int32_t)(now - lastByte) > (int32_t)RESYNC_MS) toText();
  int budget = 512;                                  // jangan menahan loop terlalu lama
  while (Serial.available() && budget--) {
    lastByte = now;
    feed((uint8_t)Serial.read(), now);
  }
}

void write(const uint8_t* frame, uint16_t n) {
  uint16_t c = crc16(frame, n);
  uint8_t head[2] = {ENV0, ENV1}, tail[2] = {(uint8_t)(c & 0xFF), (uint8_t)(c >> 8)};
  Serial.write(head, 2);
  Serial.write(frame, n);
  Serial.write(tail, 2);
}

}  // namespace link_usb
