#include "events.h"

static const uint8_t QSIZE = 8;
static Event q[QSIZE];
static uint8_t head = 0, tail = 0;

namespace events {

bool post(EventType type, int32_t value, const char* text) {
  uint8_t next = (head + 1) % QSIZE;
  if (next == tail) return false;          // penuh
  Event& e = q[head];
  e.type = type;
  e.value = value;
  if (text) strlcpy(e.text, text, sizeof(e.text)); else e.text[0] = 0;
  head = next;
  return true;
}

bool pending() { return tail != head; }

bool poll(Event& out) {
  if (tail == head) return false;
  out = q[tail];
  tail = (tail + 1) % QSIZE;
  return true;
}

}  // namespace events
