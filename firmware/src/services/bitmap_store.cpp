#include "bitmap_store.h"
#include <LittleFS.h>

// Format file: x i16, y i16, w u8, h u8, lalu data ceil(w/8)*h byte (little-endian)
static BitmapMsg cur;
static bool mounted = false;

static void path(uint8_t slot, char* p) { snprintf(p, 16, "/bmp/%u.bin", slot); }

namespace bmpstore {

bool begin() {
  // Label partisi "littlefs" (partitions.csv); partisi baru otomatis diformat sekali
  mounted = LittleFS.begin(true, "/littlefs", 4, "littlefs");
  if (mounted && !LittleFS.exists("/bmp")) LittleFS.mkdir("/bmp");
  if (!mounted) Serial.println("[bmp] littlefs gagal di-mount, slot gambar tidak tersedia");
  return mounted;
}

bool ready() { return mounted; }
BitmapMsg& current() { return cur; }

bool save(uint8_t slot, const BitmapMsg& m) {
  if (!mounted || slot < 1 || slot > SLOTS) return false;
  char p[16]; path(slot, p);
  if (m.empty()) return !LittleFS.exists(p) || LittleFS.remove(p);
  File f = LittleFS.open(p, "w");
  if (!f) return false;
  uint8_t hdr[6] = {(uint8_t)(m.x & 0xFF), (uint8_t)(m.x >> 8), (uint8_t)(m.y & 0xFF), (uint8_t)(m.y >> 8), m.w, m.h};
  bool ok = f.write(hdr, 6) == 6 && f.write(m.data, m.bytes()) == m.bytes();
  f.close();
  return ok;
}

bool load(uint8_t slot, BitmapMsg& out) {
  if (!mounted || slot < 1 || slot > SLOTS) return false;
  char p[16]; path(slot, p);
  if (!LittleFS.exists(p)) return false;
  File f = LittleFS.open(p, "r");
  if (!f) return false;
  uint8_t hdr[6];
  bool ok = f.read(hdr, 6) == 6;
  if (ok) {
    out.x = (int16_t)(hdr[0] | hdr[1] << 8);
    out.y = (int16_t)(hdr[2] | hdr[3] << 8);
    out.w = hdr[4]; out.h = hdr[5];
    out.durationS = 0;
    ok = !out.empty() && out.bytes() <= BitmapMsg::MAX_BYTES && f.read(out.data, out.bytes()) == out.bytes();
  }
  f.close();
  return ok;
}

}  // namespace bmpstore
