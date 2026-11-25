#pragma once
#include <Arduino.h>

// ============================================================
//  Lokana Link v1 — konstanta & alat bantu frame.
//  Sumber kebenaran: protocol/LOKANA_LINK.md
// ============================================================

namespace lk {

constexpr uint8_t  PROTO_VER   = 1;
constexpr uint8_t  DEVICE_TYPE = 1;       // Lokana
constexpr uint16_t MAX_PAYLOAD = 1200;    // LK_MAX_PAYLOAD
constexpr uint32_t RESYNC_MS   = 1000;    // lanjutan frame tidak datang -> buang buffer
constexpr uint8_t  ENV0 = 0xA5, ENV1 = 0x5A;

// Nomor type: JANGAN dipakai ulang / diurutkan ulang (lihat §9 spesifikasi)
enum Type : uint8_t {
  T_HELLO = 0x00, T_TIME_SYNC = 0x01, T_DEVICE_INFO = 0x02, T_SETTINGS = 0x03, T_OTA = 0x04, T_ACK = 0x05,
  T_NOTIF = 0x10, T_NAV = 0x11, T_PC_STATS = 0x12, T_MEETING = 0x13, T_PHONE_STATS = 0x14, T_CALL = 0x15,
  T_FIND_KEYS = 0x20, T_FIND_PHONE = 0x21, T_EXPRESSION = 0x22, T_DICE = 0x23, T_GOTO = 0x24, T_BUTTON = 0x25,
  T_UNPAIR = 0x06,
  T_CUSTOM_TEXT = 0x30, T_BITMAP = 0x31, T_ANIM = 0x32, T_SCREEN = 0x33, T_TEXT_SLOT = 0x34,
  T_WIFI_PROV = 0x40, T_WIFI_STATUS = 0x41,
};

enum Status : uint8_t {
  ST_OK = 0, ST_UNKNOWN_TYPE = 1, ST_BAD_PAYLOAD = 2, ST_BUSY = 3,
  ST_NOT_SUPPORTED = 4, ST_NOT_ALLOWED = 5, ST_ERROR = 6,
};

// Bit caps di DEVICE_INFO
enum Cap : uint32_t {
  CAP_NOTIF = 1u << 0, CAP_NAV = 1u << 1, CAP_PC_STATS = 1u << 2, CAP_PHONE_STATS = 1u << 3,
  CAP_CUSTOM_TEXT = 1u << 4, CAP_BITMAP = 1u << 5, CAP_OTA = 1u << 6, CAP_WIFI = 1u << 7,
  CAP_HID = 1u << 8, CAP_BUZZER = 1u << 9, CAP_DICE = 1u << 10, CAP_FIND_PHONE = 1u << 11,
  CAP_ANIM = 1u << 12, CAP_SCREEN = 1u << 13, CAP_TEXT_SLOT = 1u << 14, CAP_STATS_LAYOUT = 1u << 15,
};

const char* typeName(uint8_t t);

// Byte UTF-8 -> ASCII yang bisa ditampilkan (huruf non-ASCII jadi '?'), dipotong ke cap-1
// degree: UTF-8 '°' (C2 B0) -> 0xF7 = simbol derajat di font classic GFX (cp437 mati: 0xF7 digambar glyph 0xF8).
// Hanya untuk teks yang digambar dengan font classic (PC_STATS); font lain tidak punya glyph ini.
void toAscii(const uint8_t* s, size_t n, char* out, size_t cap, bool keepNewline = false, bool degree = false);

// CRC-16/CCITT-FALSE: poly 0x1021, init 0xFFFF, tanpa refleksi, tanpa XOR akhir
inline uint16_t crc16(uint16_t crc, uint8_t b) {
  crc ^= (uint16_t)b << 8;
  for (int i = 0; i < 8; i++) crc = (crc & 0x8000) ? (crc << 1) ^ 0x1021 : crc << 1;
  return crc;
}
uint16_t crc16(const uint8_t* p, size_t n, uint16_t crc = 0xFFFF);

// Penyusun frame dari aliran byte (dipakai BLE langsung, USB setelah envelope dibuka).
// Payload > MAX_PAYLOAD tidak disimpan, hanya dilewati (tooBig = true) supaya aliran tetap sinkron.
class FrameParser {
public:
  // true jika satu frame utuh selesai dibaca (header + len byte)
  bool feed(uint8_t b, uint32_t now);
  void reset() { _hn = 0; _got = 0; _len = 0; _tooBig = false; }
  bool idle() const { return _hn == 0; }
  bool stale(uint32_t now) const { return !idle() && (int32_t)(now - _last) > (int32_t)RESYNC_MS; }

  uint8_t type() const { return _hdr[0]; }
  uint8_t seq() const { return _hdr[1]; }
  uint16_t len() const { return _len; }
  bool tooBig() const { return _tooBig; }
  const uint8_t* payload() const { return _buf; }

private:
  uint8_t _hdr[4];
  uint8_t _hn = 0;
  uint16_t _len = 0, _got = 0;
  bool _tooBig = false;
  uint32_t _last = 0;
  uint8_t _buf[MAX_PAYLOAD];
};

// Pembaca payload dengan pengecekan batas. ok() false jika ada field yang terpotong.
class Reader {
public:
  Reader(const uint8_t* p, uint16_t n) : _p(p), _n(n) {}
  bool has() const { return _i < _n; }
  bool ok() const { return _ok; }
  uint8_t u8();
  uint16_t u16();
  int16_t i16() { return (int16_t)u16(); }
  uint32_t u32();
  uint16_t left() const { return _n - _i; }
  // n byte mentah; nullptr (dan ok() = false) jika sisa payload kurang
  const uint8_t* bytes(uint16_t n);
  // str -> ASCII yang bisa ditampilkan (huruf non-ASCII jadi '?'), dipotong ke cap-1
  void str(char* out, size_t cap, bool keepNewline = false, bool degree = false);

private:
  const uint8_t* _p;
  uint16_t _n, _i = 0;
  bool _ok = true;
};

// Penulis payload ke buffer tetap.
class Writer {
public:
  Writer(uint8_t* p, uint16_t cap) : _p(p), _cap(cap) {}
  void u8(uint8_t v) { if (_i < _cap) _p[_i++] = v; }
  void u16(uint16_t v) { u8(v & 0xFF); u8(v >> 8); }
  void u32(uint32_t v) { u16(v & 0xFFFF); u16(v >> 16); }
  void str(const char* s);
  void bytes(const uint8_t* p, uint16_t n) { while (n--) u8(*p++); }
  uint16_t len() const { return _i; }

private:
  uint8_t* _p;
  uint16_t _cap, _i = 0;
};

}  // namespace lk
