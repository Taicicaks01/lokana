"""Sampel audio -> pita frekuensi 0-255 untuk AUDIO_BANDS (Python murni, tanpa numpy).

Alur tiap frame (±25 fps):
  1. mono -> turunkan ke ±24 kHz (rata-rata 2 sampel) supaya FFT 1024 titik cukup untuk bass (resolusi ±23 Hz)
  2. jendela Hann + FFT radix-2 -> magnitudo per bin
  3. pita logaritmik 50 Hz - 12 kHz (rendah di kiri); pita yang lebih sempit dari satu bin memakai interpolasi
  4. dB + kompensasi +3 dB/oktaf (treble biasanya jauh lebih pelan) -> 0..1 terhadap referensi yang mengikuti
     puncak terakhir (penguatan otomatis: volume kecil tetap terlihat, hening tidak diperkuat jadi derau)
  5. naik cepat, turun pelan (supaya tidak berkedip)

Biaya terukur: FFT 1024 titik ±1,8 ms, jadi ±5% satu core pada 25 fps.
"""
import cmath
import math

N = 1024
F_LO, F_HI = 50.0, 12000.0
RANGE_DB = 45.0          # rentang tampil di bawah referensi
FLOOR_DB = -75.0         # referensi tidak turun di bawah ini (hening tidak diperkuat)
REF_FALL_DB = 4.0        # referensi turun 4 dB/dtk setelah bagian keras lewat
DECAY = 0.82             # pita turun ke 82% per frame (±25 fps)
SILENT_DBFS = -60.0      # di bawah ini dianggap hening


def _fft(x):
    """FFT radix-2 di tempat (list complex, panjang 2^k)."""
    n = len(x)
    j = 0
    for i in range(1, n):
        b = n >> 1
        while j & b:
            j ^= b
            b >>= 1
        j |= b
        if i < j:
            x[i], x[j] = x[j], x[i]
    m = 2
    while m <= n:
        h = m // 2
        tw = _TW[m]
        for s in range(0, n, m):
            for k in range(h):
                t = tw[k] * x[s + k + h]
                u = x[s + k]
                x[s + k] = u + t
                x[s + k + h] = u - t
        m *= 2
    return x


_TW = {}
_m = 2
while _m <= N:
    _TW[_m] = [cmath.exp(-2j * math.pi * k / _m) for k in range(_m // 2)]
    _m *= 2
_HANN = [0.5 - 0.5 * math.cos(2 * math.pi * i / (N - 1)) for i in range(N)]
_WIN_GAIN = sum(_HANN) / 2           # magnitudo sinus penuh (amplitudo 1) ~ 0 dB


class Spectrum:
    def __init__(self, bands=32, rate=48000):
        self.bands = bands
        self.set_rate(rate)
        self.buf = [0.0] * N
        self.level_db = -120.0
        self.ref = FLOOR_DB + RANGE_DB
        self.out = [0.0] * bands

    def set_rate(self, rate):
        self.rate = rate
        self.dec = 2 if rate >= 32000 else 1
        self._edges()

    def set_bands(self, n):
        if n != self.bands:
            self.bands = n
            self.out = [0.0] * n
            self._edges()

    def _edges(self):
        fs = self.rate / self.dec
        hz_per_bin = fs / N
        hi = min(F_HI, fs / 2 * 0.95)
        self.ranges = []
        for i in range(self.bands):
            f0 = F_LO * (hi / F_LO) ** (i / self.bands)
            f1 = F_LO * (hi / F_LO) ** ((i + 1) / self.bands)
            b0, b1 = f0 / hz_per_bin, f1 / hz_per_bin
            tilt = 3.0 * math.log2(math.sqrt(f0 * f1) / 1000.0)    # +3 dB/oktaf dari 1 kHz
            self.ranges.append((b0, b1, tilt))

    def push(self, samples):
        """Tambah sampel mono baru (array float) ke jendela FFT."""
        if not samples:
            return
        if self.dec == 2:
            n = len(samples) // 2 * 2
            ev, od = samples[0:n:2], samples[1:n:2]
            samples = [(a + b) * 0.5 for a, b in zip(ev, od)]
        else:
            samples = list(samples)
        if len(samples) >= N:
            self.buf = samples[-N:]
        else:
            self.buf = self.buf[len(samples):] + samples
        e = sum(v * v for v in samples) / len(samples)
        self.level_db = 10 * math.log10(e) if e > 1e-12 else -120.0

    @property
    def silent(self):
        return self.level_db < SILENT_DBFS

    def compute(self, dt):
        """Pita 0..255 (list int). dt = detik sejak frame sebelumnya (untuk referensi turun)."""
        x = [complex(v * w) for v, w in zip(self.buf, _HANN)]
        spec = _fft(x)
        mag = [abs(spec[i]) / _WIN_GAIN for i in range(N // 2)]
        raw = []
        for b0, b1, tilt in self.ranges:
            i0, i1 = int(math.ceil(b0)), int(math.floor(b1))
            if i1 >= i0:
                m = max(mag[i0:i1 + 1])
            else:                                            # pita lebih sempit dari satu bin: interpolasi
                c = (b0 + b1) / 2
                k = int(c)
                f = c - k
                m = mag[k] * (1 - f) + mag[min(k + 1, N // 2 - 1)] * f
            raw.append(20 * math.log10(m + 1e-9) + tilt)
        peak = max(raw)
        self.ref = max(peak, self.ref - REF_FALL_DB * dt, FLOOR_DB + RANGE_DB)
        lo = self.ref - RANGE_DB
        out = []
        for i, db in enumerate(raw):
            v = max(0.0, min(1.0, (db - lo) / RANGE_DB))
            v = v * v                                        # kontras: hanya bagian keras yang tinggi
            prev = self.out[i] * DECAY
            self.out[i] = v if v > prev else prev
            out.append(int(self.out[i] * 255 + 0.5))
        return out

    def decay(self):
        """Frame saat hening: pita turun pelan ke nol."""
        for i in range(len(self.out)):
            self.out[i] *= DECAY
        return [int(v * 255 + 0.5) for v in self.out]


if __name__ == "__main__":             # uji: sinus 100 Hz / 1 kHz / 8 kHz -> pita tertinggi di kiri / tengah / kanan
    import time
    sp = Spectrum(32, 48000)
    for f in (100, 1000, 8000):
        sig = [0.5 * math.sin(2 * math.pi * f * i / 48000) for i in range(4096)]
        sp.out = [0.0] * 32
        sp.push(sig)
        b = sp.compute(0.04)
        print("%5d Hz -> pita tertinggi %2d  %s" % (f, b.index(max(b)), "".join(" .:-=+*#%@"[v * 10 // 256] for v in b)))
    t = time.perf_counter()
    for _ in range(25):
        sp.push(sig[:1920])
        sp.compute(0.04)
    print("25 frame: %.0f ms (= beban per detik)" % ((time.perf_counter() - t) * 1000))
