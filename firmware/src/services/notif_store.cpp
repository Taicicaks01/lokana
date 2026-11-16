#include "notif_store.h"

static Notif list[notifstore::MAX];   // list[0] = terbaru
static uint8_t n = 0;
static bool ringing = false;
static char callerName[41] = {0};

namespace notifstore {

bool upsert(const Notif& x) {
  for (uint8_t i = 0; i < n; i++)
    if (list[i].id == x.id) { list[i] = x; list[i].at = millis(); return false; }
  for (uint8_t i = (n < MAX ? n : MAX - 1); i > 0; i--) list[i] = list[i - 1];   // geser, buang terlama
  list[0] = x;
  list[0].at = millis();
  if (n < MAX) n++;
  return true;
}

void removeAt(uint8_t i) {
  if (i >= n) return;
  for (; i + 1 < n; i++) list[i] = list[i + 1];
  n--;
  list[n] = Notif();
}

bool remove(uint32_t id) {
  for (uint8_t i = 0; i < n; i++)
    if (list[i].id == id) { removeAt(i); return true; }
  return false;
}

void clear() { while (n) removeAt(0); }
uint8_t count() { return n; }
const Notif& at(uint8_t i) { return list[i < n ? i : 0]; }

void setCall(bool r, const char* c) {
  ringing = r;
  if (c) strlcpy(callerName, c, sizeof(callerName));
}
bool callRinging() { return ringing; }
const char* caller() { return callerName; }

}  // namespace notifstore
