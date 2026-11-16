#pragma once
#include <Arduino.h>

// Bungkus kata: baris maks `cols` karakter, '\n' = baris baru, kata terlalu panjang dipotong
template <typename L>
inline uint8_t wrapText(const char* t, int cols, L* out, uint8_t maxLines) {
  int len = strlen(t), s = 0;
  uint8_t n = 0;
  while (s <= len && n < maxLines) {
    int e = s, sp = -1;
    while (e < len && t[e] != '\n' && e - s < cols) { if (t[e] == ' ') sp = e; e++; }
    if (e >= len || t[e] == '\n') {                 // sisa muat di satu baris
      out[n++] = {(uint8_t)s, (uint8_t)(e - s)};
      if (e >= len) break;
      s = e + 1;
    } else if (t[e] == ' ') { out[n++] = {(uint8_t)s, (uint8_t)(e - s)}; s = e + 1; }
    else if (sp > s)        { out[n++] = {(uint8_t)s, (uint8_t)(sp - s)}; s = sp + 1; }
    else                    { out[n++] = {(uint8_t)s, (uint8_t)cols}; s += cols; }
  }
  return n;
}
