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
  EV_BITMAP,       // gambar/animasi baru di imgstore::current() siap ditampilkan (modul Gambar)
  EV_FIND_PHONE,   // value = 1 mulai memanggil HP (menu), 0 HP sudah ditemukan (dari HP)
  EV_NOTIF,        // value = 1 notifikasi baru (notifstore::at(0)), 0 diperbarui/dihapus
  EV_CALL,         // value = 0 berdering (penelepon di notifstore::caller()), 1 selesai
  EV_SPLASH,       // putar ulang splash boot; value > 0 = bekukan di ms tersebut (uji/screenshot)
  EV_GUIDE,        // putar Panduan cara pakai; value > 0 = bekukan di ms tersebut (uji/screenshot)
  EV_LEFT,         // pengingat ketinggalan: value 1 = HP tertinggal, 0 = HP tersambung lagi
  EV_OTA,          // pembaruan firmware: 1 mulai, 2 terpasang (restart), 3 ditandai valid, -alasan gagal,
                   // -100 firmware baru gagal boot dan sudah kembali ke versi lama
  EV_NAV,          // navigasi (navstore): 1 mulai, 2 belokan baru, 3 < 300 m ke belokan, 0 selesai (text = pesan)
  EV_STATS,        // monitor PC (statsstore): 1 data mulai masuk, 0 berhenti (10 dtk tanpa data)
  EV_AUDIO,        // visualizer audio PC (audiostore): 1 mulai, 0 berhenti (1,5 dtk tanpa pesan)
};

struct Event {
  EventType type = EV_NONE;
  int32_t value = 0;
  char text[32] = {0};
};

namespace events {
bool post(EventType type, int32_t value = 0, const char* text = nullptr);
bool poll(Event& out);
bool pending();                              // ada event di antrian (tanpa mengambilnya)
}
