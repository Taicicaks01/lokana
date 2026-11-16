#pragma once
#include <Arduino.h>

// Event bus sederhana: antrian kejadian yang diteruskan Core ke semua modul.
enum EventType : uint8_t {
  EV_NONE,
  EV_EXPRESSION,   // value = ID ekspresi | (hold_ms << 8); hold 0 = default
  EV_ROLL,         // minta modul Dadu melempar; value = ID dadu, 255 = jenis yang sedang dipilih
  EV_GOTO,         // text = nama modul tujuan
  EV_TOAST,        // text = pesan singkat
  EV_SETTINGS,     // pengaturan berubah
  EV_TEXT,         // teks baru di text_store siap ditampilkan (modul Teks)
  EV_FIND_KEYS,    // value = lama bunyi (detik), 0 = berhenti
  EV_PAIR_CODE,    // value = passkey 6 digit yang harus diketik di HP
  EV_PAIR_DONE,    // value = 1 berhasil, 0 gagal/batal
  EV_BITMAP,       // gambar baru di bmpstore siap ditampilkan (modul Gambar)
  EV_FIND_PHONE,   // value = 1 mulai memanggil HP (menu), 0 HP sudah ditemukan (dari HP)
};

struct Event {
  EventType type = EV_NONE;
  int32_t value = 0;
  char text[32] = {0};
};

namespace events {
bool post(EventType type, int32_t value = 0, const char* text = nullptr);
bool poll(Event& out);
}
