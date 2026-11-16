#include "oled_text.h"

// Satu kode UTF-8 -> code point. Hasil 0xFFFD jika rusak. `len` = jumlah byte yang dipakai.
static uint32_t decode(const uint8_t* s, size_t n, uint8_t& len) {
  uint8_t c = s[0];
  uint8_t need = c < 0x80 ? 0 : (c & 0xE0) == 0xC0 ? 1 : (c & 0xF0) == 0xE0 ? 2 : (c & 0xF8) == 0xF0 ? 3 : 0xFF;
  if (need == 0xFF || (size_t)need + 1 > n) { len = 1; return c < 0x80 ? c : 0xFFFD; }
  uint32_t cp = need == 0 ? c : need == 1 ? (c & 0x1F) : need == 2 ? (c & 0x0F) : (c & 0x07);
  for (uint8_t i = 1; i <= need; i++) {
    if ((s[i] & 0xC0) != 0x80) { len = 1; return 0xFFFD; }
    cp = cp << 6 | (s[i] & 0x3F);
  }
  len = need + 1;
  return cp;
}

void sanitizeUtf8(const uint8_t* in, size_t n, char* out, size_t maxBytes) {
  size_t o = 0, i = 0;
  while (i < n) {
    uint8_t len;
    uint32_t cp = decode(in + i, n - i, len);
    if (cp != 0xFFFD && cp >= 0x20 && cp != 0x7F && (cp < 0x80 || cp >= 0xA0)) {
      if (o + len > maxBytes) break;               // jangan memutus karakter
      memcpy(out + o, in + i, len);
      o += len;
    }
    i += len;
  }
  out[o] = 0;
}

// Dewanagari (U+0900-U+097F) -> Latin sederhana (gaya IAST tanpa diakritik)
static const char* const CONS[] = {             // U+0915 .. U+0939
  "k", "kh", "g", "gh", "n", "c", "ch", "j", "jh", "n", "t", "th", "d", "dh", "n",
  "t", "th", "d", "dh", "n", "n", "p", "ph", "b", "bh", "m", "y", "r", "r", "l", "l", "l",
  "v", "s", "s", "s", "h"};
static const char* const VOW[] = {              // U+0905 .. U+0914 (vokal mandiri)
  "a", "a", "i", "i", "u", "u", "ri", "li", "e", "e", "e", "ai", "o", "o", "o", "au"};
static const char* const SIGN[] = {             // U+093E .. U+094C (tanda vokal)
  "a", "i", "i", "u", "u", "ri", "ri", "e", "e", "e", "ai", "o", "o", "o", "au"};
// Latin-1 U+00C0 .. U+00FF -> huruf dasar
static const char LATIN1[] = "AAAAAAACEEEEIIIIDNOOOOOxOUUUUYPsaaaaaaaceeeeiiiidnooooo/ouuuuypy";

void toOledText(const char* utf8, char* out, size_t cap) {
  if (!cap) return;
  size_t o = 0, n = strlen(utf8), i = 0;
  bool pendingA = false;                          // konsonan Dewanagari menunggu vokal
  auto put = [&](const char* s) { while (*s && o + 1 < cap) out[o++] = *s++; };
  auto putc_ = [&](char c) { if (o + 1 < cap) out[o++] = c; };
  while (i < n && o + 1 < cap) {
    uint8_t len;
    uint32_t cp = decode((const uint8_t*)utf8 + i, n - i, len);
    i += len;
    bool isSign = cp >= 0x093E && cp <= 0x094C, isVirama = cp == 0x094D;
    if (pendingA && !isSign && !isVirama && cp != 0x093C) { putc_('a'); pendingA = false; }
    if (cp < 0x80) putc_(cp >= 0x20 ? (char)cp : ' ');
    else if (cp >= 0x0915 && cp <= 0x0939) { put(CONS[cp - 0x0915]); pendingA = true; }
    else if (isSign) { put(SIGN[cp - 0x093E]); pendingA = false; }
    else if (isVirama) pendingA = false;
    else if (cp >= 0x0905 && cp <= 0x0914) put(VOW[cp - 0x0905]);
    else if (cp == 0x0901) putc_('n');
    else if (cp == 0x0902) putc_('m');
    else if (cp == 0x0903) putc_('h');
    else if (cp == 0x093C) {}                       // nukta
    else if (cp >= 0x0966 && cp <= 0x096F) putc_('0' + (cp - 0x0966));
    else if (cp == 0x0964 || cp == 0x0965) putc_('.');
    else if (cp >= 0xC0 && cp <= 0xFF) putc_(LATIN1[cp - 0xC0]);
    else putc_('?');
  }
  if (pendingA) putc_('a');
  out[o] = 0;
}
