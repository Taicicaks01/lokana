#include "link_proto.h"

namespace lk {

const char* typeName(uint8_t t) {
  switch (t) {
    case T_HELLO: return "HELLO";             case T_TIME_SYNC: return "TIME_SYNC";
    case T_DEVICE_INFO: return "DEVICE_INFO"; case T_SETTINGS: return "SETTINGS";
    case T_OTA: return "OTA";                 case T_ACK: return "ACK";
    case T_NOTIF: return "NOTIF";             case T_NAV: return "NAV";
    case T_PC_STATS: return "PC_STATS";       case T_MEETING: return "MEETING";
    case T_AUDIO_BANDS: return "AUDIO_BANDS";
    case T_PHONE_STATS: return "PHONE_STATS"; case T_CALL: return "CALL";
    case T_FIND_KEYS: return "FIND_KEYS";     case T_FIND_PHONE: return "FIND_PHONE";
    case T_EXPRESSION: return "EXPRESSION";   case T_DICE: return "DICE";
    case T_GOTO: return "GOTO";               case T_BUTTON: return "BUTTON";
    case T_CUSTOM_TEXT: return "CUSTOM_TEXT"; case T_BITMAP: return "BITMAP";
    case T_ANIM: return "ANIM";               case T_UNPAIR: return "UNPAIR";
    case T_TEXT_SLOT: return "TEXT_SLOT";
    case T_SCREEN: return "SCREEN";
    case T_WIFI_PROV: return "WIFI_PROV";     case T_WIFI_STATUS: return "WIFI_STATUS";
    default: return "?";
  }
}

uint16_t crc16(const uint8_t* p, size_t n, uint16_t crc) {
  while (n--) crc = crc16(crc, *p++);
  return crc;
}

// ---------------- FrameParser ----------------
bool FrameParser::feed(uint8_t b, uint32_t now) {
  if (stale(now)) reset();
  _last = now;
  if (_hn < 4) {
    _hdr[_hn++] = b;
    if (_hn < 4) return false;
    _len = _hdr[2] | (uint16_t)_hdr[3] << 8;
    _got = 0;
    _tooBig = _len > MAX_PAYLOAD;
    if (_len == 0) { _hn = 0; return true; }
    return false;
  }
  if (!_tooBig) _buf[_got] = b;
  if (++_got < _len) return false;
  _hn = 0;                     // frame selesai; header berikutnya mulai dari awal
  return true;
}

// ---------------- Reader ----------------
uint8_t Reader::u8() {
  if (_i + 1 > _n) { _ok = false; return 0; }
  return _p[_i++];
}

uint16_t Reader::u16() {
  if (_i + 2 > _n) { _ok = false; _i = _n; return 0; }
  uint16_t v = _p[_i] | (uint16_t)_p[_i + 1] << 8;
  _i += 2;
  return v;
}

uint32_t Reader::u32() {
  if (_i + 4 > _n) { _ok = false; _i = _n; return 0; }
  uint32_t v = _p[_i] | (uint32_t)_p[_i + 1] << 8 | (uint32_t)_p[_i + 2] << 16 | (uint32_t)_p[_i + 3] << 24;
  _i += 4;
  return v;
}

const uint8_t* Reader::bytes(uint16_t n) {
  if (_i + n > _n) { _ok = false; _i = _n; return nullptr; }
  const uint8_t* p = _p + _i;
  _i += n;
  return p;
}

void Reader::str(char* out, size_t cap, bool keepNewline, bool degree) {
  uint8_t n = u8();
  if (!_ok) { if (cap) out[0] = 0; return; }
  if (_i + n > _n) { _ok = false; n = _n - _i; }
  const uint8_t* s = _p + _i;
  _i += n;
  toAscii(s, n, out, cap, keepNewline, degree);
}

void toAscii(const uint8_t* s, size_t n, char* out, size_t cap, bool keepNewline, bool degree) {
  size_t o = 0;
  for (size_t k = 0; k < n && o + 1 < cap; k++) {
    uint8_t c = s[k];
    if (degree && c == 0xC2 && k + 1 < n && s[k + 1] == 0xB0) { out[o++] = (char)0xF7; k++; continue; }
    if (c >= 0x80) {
      if ((c & 0xC0) == 0x80) continue;          // byte lanjutan UTF-8: sudah diwakili '?'
      out[o++] = '?';
    } else if (c == '\n' && keepNewline) out[o++] = '\n';
    else out[o++] = (c < 0x20 || c == 0x7F) ? ' ' : (char)c;
  }
  if (cap) out[o] = 0;
}

// ---------------- Writer ----------------
void Writer::str(const char* s) {
  size_t n = strlen(s);
  if (n > 255) n = 255;
  u8((uint8_t)n);
  for (size_t i = 0; i < n; i++) u8((uint8_t)s[i]);
}

}  // namespace lk
