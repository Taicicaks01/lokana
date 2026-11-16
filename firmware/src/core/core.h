#pragma once
#include "core/module.h"

// Inti Lokana OS: daftar modul, perpindahan modul, menu, toast, dan manajemen layar.
namespace core {
void begin();
void loop();
void addModule(Module* m);       // modul pertama = layar utama (home)
// announce: tampilkan nama modul sebentar di atas. Modul yang membuka dirinya karena event
// (notifikasi, gambar masuk) memakai false supaya isinya tidak tertutup.
bool goTo(const char* name, bool announce = false);
// Buka modul setelah ms, hanya jika pengguna belum menyentuh dan modul aktif belum berganti.
void goToLater(const char* name, uint32_t ms);
void next();
void back();                     // kembali ke modul (tidak tersembunyi) sebelumnya
void openMenu();
void toast(const char* text, uint16_t ms = 1200);
void wake();                     // nyalakan layar & reset timer diam
void sleepScreen();              // matikan layar
void injectGesture(Gesture g);   // untuk uji lewat serial
uint8_t moduleCount();
Module* moduleAt(uint8_t i);
Module* current();
bool screenOn();
uint32_t loopMaxMs();             // putaran loop terlama dalam ~1 detik terakhir (diagnostik)
}
