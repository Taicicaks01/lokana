#include "buzzer.h"
#include "config.h"
#include "core/settings.h"

struct Note { uint16_t f; uint16_t ms; };   // f=0 jeda, ms=0 akhir

static const Note N_BOOT[]  = {{523, 70}, {659, 70}, {784, 70}, {1047, 140}, {0, 0}};
static const Note N_TAP[]   = {{1319, 35}, {1760, 45}, {0, 0}};
static const Note N_HAPPY[] = {{784, 55}, {988, 55}, {1319, 90}, {0, 0}};
static const Note N_ANGRY[] = {{220, 110}, {0, 30}, {196, 160}, {0, 0}};
static const Note N_MENU[]  = {{1047, 30}, {0, 0}};
static const Note N_SEL[]   = {{1568, 45}, {0, 0}};
static const Note N_SLEEP[] = {{784, 110}, {659, 110}, {523, 200}, {0, 0}};
static const Note N_WAKE[]  = {{523, 70}, {784, 110}, {0, 0}};
static const Note N_TICK[]  = {{2093, 12}, {0, 0}};
static const Note N_DONE[]  = {{1319, 60}, {1760, 120}, {0, 0}};
static const Note N_WIN[]   = {{1047, 70}, {1319, 70}, {1568, 70}, {2093, 180}, {0, 0}};
static const Note N_LOSE[]  = {{392, 120}, {330, 120}, {262, 220}, {0, 0}};
static const Note N_LOVE[]  = {{1047, 80}, {1319, 80}, {1047, 80}, {1568, 140}, {0, 0}};
static const Note N_FIND[]  = {{2093, 90}, {0, 40}, {2637, 90}, {0, 40}, {2093, 90}, {0, 40}, {2637, 90}, {0, 300}, {0, 0}};
static const Note N_PAIR[]  = {{1568, 60}, {0, 40}, {1568, 60}, {0, 0}};
static const Note N_NOTIF[] = {{1568, 60}, {0, 40}, {2093, 90}, {0, 0}};
static const Note N_NOTHI[] = {{2093, 70}, {0, 40}, {2093, 70}, {0, 40}, {2637, 140}, {0, 0}};
static const Note N_CALL[]  = {{1319, 70}, {1047, 70}, {1319, 70}, {1047, 70}, {1319, 70}, {1047, 70},
                               {1319, 70}, {1047, 70}, {0, 1400}, {0, 0}};

static const Note* MEL[MEL_COUNT] = {
  N_BOOT, N_TAP, N_HAPPY, N_ANGRY, N_MENU, N_SEL, N_SLEEP, N_WAKE, N_TICK, N_DONE, N_WIN, N_LOSE, N_LOVE,
  N_FIND, N_PAIR, N_NOTIF, N_NOTHI, N_CALL
};

static const Note* cur = nullptr;
static uint8_t idx = 0;
static uint32_t noteEnd = 0;

#if PIN_BUZZER >= 0
  #if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
    #define TONE(f) ledcWriteTone(PIN_BUZZER, (f))
  #else
    #define TONE(f) ledcWriteTone(0, (f))
  #endif
#else
  #define TONE(f) ((void)0)
#endif

static void startNote(uint32_t now) {
  const Note& n = cur[idx];
  if (n.ms == 0) { buzzer::stop(); return; }
  TONE(n.f);
  noteEnd = now + n.ms;
}

namespace buzzer {

void begin() {
#if PIN_BUZZER >= 0
  #if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
  ledcAttach(PIN_BUZZER, 2000, 10);
  #else
  ledcSetup(0, 2000, 10);
  ledcAttachPin(PIN_BUZZER, 0);
  #endif
  TONE(0);
#endif
}

void play(Melody m, bool force) {
  if ((!settings::get().sound && !force) || m >= MEL_COUNT) return;
  cur = MEL[m];
  idx = 0;
  startNote(millis());
}

void update(uint32_t now) {
  if (cur && (int32_t)(now - noteEnd) >= 0) { idx++; startNote(now); }
}

void stop() { cur = nullptr; TONE(0); }

bool playing() { return cur != nullptr; }

}  // namespace buzzer
