#include "text_store.h"
#include <Preferences.h>

static TextMsg cur;

// Format blob di NVS: style, size | (font << 4), lalu teks (tanpa null). Slot lama: font 0.
static void key(uint8_t slot, char* k) { snprintf(k, 4, "s%u", slot); }

namespace textstore {

TextMsg& current() { return cur; }
void setCurrent(const TextMsg& m) { cur = m; }

bool save(uint8_t slot, const TextMsg& m) {
  if (slot < 1 || slot > SLOTS) return false;
  uint8_t blob[2 + sizeof(m.text)];
  size_t n = strnlen(m.text, sizeof(m.text) - 1);
  blob[0] = m.style; blob[1] = (m.size & 0x0F) | (m.font << 4);
  memcpy(blob + 2, m.text, n);
  char k[4]; key(slot, k);
  Preferences p;
  p.begin("lktext", false);
  bool ok = n ? p.putBytes(k, blob, n + 2) == n + 2 : p.remove(k);
  p.end();
  return ok;
}

bool load(uint8_t slot, TextMsg& out) {
  if (slot < 1 || slot > SLOTS) return false;
  uint8_t blob[2 + sizeof(out.text)];
  char k[4]; key(slot, k);
  Preferences p;
  p.begin("lktext", true);
  size_t n = p.isKey(k) ? p.getBytes(k, blob, sizeof(blob) - 1) : 0;
  p.end();
  if (n < 3) return false;
  out = TextMsg();
  out.style = blob[0]; out.size = blob[1] & 0x0F; out.font = blob[1] >> 4;
  if (out.font >= FONTS) out.font = 0;
  memcpy(out.text, blob + 2, n - 2);
  out.text[n - 2] = 0;
  return true;
}

}  // namespace textstore
