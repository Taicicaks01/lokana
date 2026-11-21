#pragma once
#include <Arduino.h>

// Buzzer pasif, melodi non-blocking. Tanpa buzzer (PIN_BUZZER = -1) semua fungsi diam.
enum Melody : uint8_t {
  MEL_BOOT, MEL_TAP, MEL_HAPPY, MEL_ANGRY, MEL_MENU, MEL_SELECT,
  MEL_SLEEP, MEL_WAKE, MEL_TICK, MEL_ROLL_DONE, MEL_WIN, MEL_LOSE, MEL_LOVE,
  MEL_FIND, MEL_PAIR, MEL_NOTIF, MEL_NOTIF_HI, MEL_CALL,
  MEL_COUNT
};

namespace buzzer {
void begin();
void play(Melody m, bool force = false);   // force: bunyi walau suara dimatikan (cari kunci)
bool playing();
void update(uint32_t now);
void stop();
// Diagnostik (console `tone` / `sweep`): bunyi satu frekuensi, mengabaikan setelan suara. 0 = diam.
void raw(uint16_t hz);
void tone(uint16_t hz, uint16_t ms);
}
