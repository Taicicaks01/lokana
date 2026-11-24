#include "stats_store.h"

static Metric metrics[statsstore::MAX];
static uint8_t n = 0;
static bool on = false;
static uint32_t at = 0;

namespace statsstore {

uint8_t count() { return on ? n : 0; }
const Metric& get(uint8_t i) { return metrics[i < MAX ? i : 0]; }

bool update(const Metric* m, uint8_t cnt) {
  bool was = on;
  n = cnt > MAX ? MAX : cnt;
  for (uint8_t i = 0; i < n; i++) metrics[i] = m[i];
  on = true;
  at = millis();
  return !was;
}

bool active() { return on; }

bool tick(uint32_t now) {
  if (!on || (int32_t)(now - at) < (int32_t)STALE_MS) return false;
  on = false;
  n = 0;
  return true;
}

}  // namespace statsstore
