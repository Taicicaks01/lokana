#pragma once

// Konsol perintah teks lewat USB serial (pengembangan & uji di Wokwi).
// Port USB yang sama juga membawa frame Lokana Link; link_usb memisahkan keduanya
// dan meneruskan byte teks ke sini.
namespace console {
void begin();
void feed(char c);
}
