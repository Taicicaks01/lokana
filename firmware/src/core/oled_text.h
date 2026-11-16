#pragma once
#include <Arduino.h>

// Font OLED hanya ASCII. Ubah teks UTF-8 menjadi teks yang bisa ditampilkan:
//  - Dewanagari -> huruf Latin (लोचन -> "locana"), dengan vokal bawaan 'a' dan virama
//  - huruf Latin beraksen -> huruf dasar (é -> e)
//  - lainnya -> '?'
void toOledText(const char* utf8, char* out, size_t cap);

// Bersihkan UTF-8 dari host: buang urutan tidak valid & karakter kontrol,
// potong maksimal maxBytes tanpa memutus karakter. Hasil selalu diakhiri null.
void sanitizeUtf8(const uint8_t* in, size_t n, char* out, size_t maxBytes);
