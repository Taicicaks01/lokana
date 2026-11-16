#include "image_store.h"
#include <LittleFS.h>

// Format file /img/N.bin (little-endian):
//   "LKA1" | frames u8 | loops u8 | frame_ms u16 | x i16 | y i16 | w u8 | h u8 | data (frames x ceil(w/8)*h)
static const uint8_t MAGIC[4] = {'L', 'K', 'A', '1'};
static const uint8_t HDR = 14;

static Anim cur;
static bool mounted = false;

static void path(uint8_t slot, char* p) { snprintf(p, 16, "/img/%u.bin", slot); }

bool Anim::alloc() {
  release();
  if (!frames || frames > MAX_FRAMES || !w || w > 128 || !h || h > 64 || totalBytes() > MAX_BYTES) return false;
  data = (uint8_t*)calloc(1, totalBytes());
  return data != nullptr;
}

void Anim::release() {
  free(data);
  data = nullptr;
}

void Anim::swap(Anim& o) {
  std::swap(frames, o.frames); std::swap(loops, o.loops); std::swap(w, o.w); std::swap(h, o.h);
  std::swap(frameMs, o.frameMs); std::swap(durationS, o.durationS);
  std::swap(x, o.x); std::swap(y, o.y); std::swap(data, o.data);
}

static bool readHeader(File& f, Anim& a) {
  uint8_t h[HDR];
  if (f.read(h, HDR) != HDR || memcmp(h, MAGIC, 4)) return false;
  a.frames = h[4]; a.loops = h[5];
  a.frameMs = h[6] | h[7] << 8;
  a.x = (int16_t)(h[8] | h[9] << 8);
  a.y = (int16_t)(h[10] | h[11] << 8);
  a.w = h[12]; a.h = h[13];
  a.durationS = 0;
  return true;
}

namespace imgstore {

bool begin() {
  // Label partisi "littlefs" (partitions.csv); partisi baru otomatis diformat sekali
  mounted = LittleFS.begin(true, "/littlefs", 4, "littlefs");
  if (mounted && !LittleFS.exists("/img")) LittleFS.mkdir("/img");
  if (!mounted) Serial.println("[img] littlefs gagal di-mount, slot gambar tidak tersedia");
  return mounted;
}

bool ready() { return mounted; }
Anim& current() { return cur; }

bool save(uint8_t slot, const Anim& a) {
  if (!mounted || slot < 1 || slot > SLOTS) return false;
  if (a.empty()) return remove(slot);
  char p[16]; path(slot, p);
  File f = LittleFS.open(p, "w");
  if (!f) return false;
  uint8_t h[HDR] = {'L', 'K', 'A', '1', a.frames, a.loops,
                    (uint8_t)(a.frameMs & 0xFF), (uint8_t)(a.frameMs >> 8),
                    (uint8_t)(a.x & 0xFF), (uint8_t)((uint16_t)a.x >> 8),
                    (uint8_t)(a.y & 0xFF), (uint8_t)((uint16_t)a.y >> 8), a.w, a.h};
  bool ok = f.write(h, HDR) == HDR && f.write(a.data, a.totalBytes()) == a.totalBytes();
  f.close();
  if (!ok) LittleFS.remove(p);
  return ok;
}

bool load(uint8_t slot, Anim& out, bool firstOnly) {
  if (!mounted || slot < 1 || slot > SLOTS) return false;
  char p[16]; path(slot, p);
  if (!LittleFS.exists(p)) return false;
  File f = LittleFS.open(p, "r");
  if (!f) return false;
  bool ok = readHeader(f, out);
  if (ok && firstOnly) out.frames = 1;
  ok = ok && out.alloc() && f.read(out.data, out.totalBytes()) == out.totalBytes();
  f.close();
  if (!ok) out.release();
  return ok;
}

bool remove(uint8_t slot) {
  if (!mounted || slot < 1 || slot > SLOTS) return false;
  char p[16]; path(slot, p);
  return !LittleFS.exists(p) || LittleFS.remove(p);
}

bool info(uint8_t slot, uint8_t& frames, uint8_t& w, uint8_t& h) {
  frames = w = h = 0;
  if (!mounted || slot < 1 || slot > SLOTS) return false;
  char p[16]; path(slot, p);
  if (!LittleFS.exists(p)) return false;
  File f = LittleFS.open(p, "r");
  Anim a;
  bool ok = f && readHeader(f, a);
  if (f) f.close();
  if (ok) { frames = a.frames; w = a.w; h = a.h; }
  return ok;
}

}  // namespace imgstore
