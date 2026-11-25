#include "stats_store.h"

static Metric metrics[statsstore::MAX];
static uint8_t n = 0;
static StatRow layout[statsstore::MAX];
static uint8_t nrows = 0;                // 0 = satu metrik per baris
static bool on = false;
static uint32_t at = 0;

namespace statsstore {

uint8_t count() { return on ? n : 0; }
const Metric& get(uint8_t i) { return metrics[i < MAX ? i : 0]; }

bool update(const Metric* m, uint8_t cnt, const StatRow* rows, uint8_t rcnt) {
  bool was = on;
  n = cnt > MAX ? MAX : cnt;
  for (uint8_t i = 0; i < n; i++) metrics[i] = m[i];
  nrows = rows ? (rcnt > MAX ? MAX : rcnt) : 0;
  for (uint8_t i = 0; i < nrows; i++) layout[i] = rows[i];
  on = true;
  at = millis();
  return !was;
}

bool active() { return on; }

uint8_t rowCount() { return !on ? 0 : nrows ? nrows : n; }

StatRow row(uint8_t i) {
  if (nrows) return layout[i < MAX ? i : 0];
  StatRow r;
  r.a = i;
  return r;
}

bool tick(uint32_t now) {
  if (!on || (int32_t)(now - at) < (int32_t)STALE_MS) return false;
  on = false;
  n = 0;
  return true;
}

}  // namespace statsstore
