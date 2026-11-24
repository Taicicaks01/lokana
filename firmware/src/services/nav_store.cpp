#include "nav_store.h"

static NavInfo cur;

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
  if (!was) return NV_START;
  if (turn) return NV_TURN;
  // Masuk radius dekat (termasuk dari "tidak diketahui"): sekali per belokan
  if (cur.distM <= NEAR_M && prevDist > NEAR_M) return NV_NEAR;
  return NV_NONE;
}

bool stop() {
  bool was = cur.active;
  cur = NavInfo();
  return was;
}

bool tick(uint32_t now) {
  if (!cur.active || (int32_t)(now - cur.at) < (int32_t)STALE_MS) return false;
  cur = NavInfo();
  return true;
}

bool near() { return cur.active && cur.distM <= NEAR_M; }

}  // namespace navstore
