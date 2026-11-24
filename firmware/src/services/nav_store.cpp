#include "nav_store.h"

static NavInfo cur;

// Redam Maps yang bolak-balik antara dua instruksi saat HP diam (GPS belum stabil, data asli 2026-11-24):
// A -> B -> A -> B. Belokan baru yang sama dengan belokan sebelum-terakhir dalam 60 dtk = bolak-balik:
// datanya tetap diperbarui, tapi tanpa event (layar tidak dinyalakan, tanpa bunyi).
static const uint32_t FLIP_MS = 60000;
static uint32_t key1 = 0, key2 = 0;     // belokan sekarang & sebelumnya (hash instruksi + jalan + ikon)
static uint32_t turnAt = 0;

static uint32_t fnv(uint32_t h, const uint8_t* p, size_t n) {
  for (size_t i = 0; i < n; i++) { h ^= p[i]; h *= 16777619u; }
  return h;
}

static uint32_t keyOf(const NavInfo& n) {
  uint32_t h = 2166136261u;
  h = fnv(h, (const uint8_t*)n.instr, strlen(n.instr));
  h = fnv(h, (const uint8_t*)"|", 1);
  h = fnv(h, (const uint8_t*)n.street, strlen(n.street));
  return fnv(h, n.icon, ((n.iconW + 7) / 8) * n.iconH);
}

namespace navstore {

const NavInfo& get() { return cur; }

uint8_t update(const NavInfo& in) {
  const bool was = cur.active;
  const uint32_t prevDist = cur.distM;
  const uint16_t iconBytes = ((in.iconW + 7) / 8) * in.iconH;
  const bool turn = strcmp(in.instr, cur.instr) || strcmp(in.street, cur.street) || in.iconW != cur.iconW ||
                    in.iconH != cur.iconH || memcmp(in.icon, cur.icon, iconBytes);
  const uint32_t changedAt = cur.changedAt;
  cur = in;
  cur.active = true;
  cur.at = millis();
  cur.changedAt = (turn || !was) ? cur.at : changedAt;
  if (!was) {
    key1 = keyOf(cur); key2 = 0; turnAt = cur.at;
    return NV_START;
  }
  if (turn) {
    const uint32_t k = keyOf(cur);
    const bool flip = k == key2 && (int32_t)(cur.at - turnAt) < (int32_t)FLIP_MS;
    key2 = key1; key1 = k; turnAt = cur.at;
    return flip ? NV_NONE : NV_TURN;
  }
  // Masuk radius dekat (termasuk dari "tidak diketahui"): sekali per belokan
  if (cur.distM <= NEAR_M && prevDist > NEAR_M) return NV_NEAR;
  return NV_NONE;
}

bool stop() {
  bool was = cur.active;
  cur = NavInfo();
  key1 = key2 = 0;
  return was;
}

bool tick(uint32_t now) {
  if (!cur.active || (int32_t)(now - cur.at) < (int32_t)STALE_MS) return false;
  cur = NavInfo();
  key1 = key2 = 0;
  return true;
}

bool near() { return cur.active && cur.distM <= NEAR_M; }

}  // namespace navstore
