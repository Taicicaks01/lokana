#pragma once
#include <Arduino.h>

// LED bawaan & baterai (opsional)
namespace led {
void begin();
void pulse(uint16_t ms);
void update(uint32_t now);
}

namespace battery {
void begin();
void update(uint32_t now);
float volts();         // tegangan sel terfilter (V); 0 = tidak terbaca (tanpa sensor / saklar OFF + USB)
int percent();         // 0..100, -1 = tidak terbaca
uint16_t millivolts(); // tegangan sel (mV), 0 = tidak terbaca
bool charging();       // charger TP4056 dicolok (GPIO4, ADC)
bool low();            // di bawah BATT_WARN_V (histeresis 0.1 V)
bool critical();       // di bawah BATT_CUTOFF_V 10 bacaan berturut-turut, tanpa charger / USB komputer
bool externalPower();  // dapat daya luar: charger, USB komputer, atau baterai tidak terbaca
float divider();       // faktor pembagi aktif (kalibrasi NVS atau BATT_DIVIDER)
bool calibrated();
bool calibrate(float realV);   // dari tegangan sel hasil multimeter; false jika di luar 1.6..2.6
void resetCalibration();
uint16_t pinMv();      // mV mentah GPIO baterai (rata-rata 16 sampel)
uint16_t chgMv();      // mV mentah GPIO deteksi charge
}
