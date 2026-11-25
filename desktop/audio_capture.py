"""Tangkap suara yang diputar PC (WASAPI loopback, Windows) tanpa pustaka tambahan: COM lewat ctypes.

    cap = LoopbackCapture()
    cap.open()                 # perangkat output bawaan (speaker / headset)
    samples = cap.read()       # sampel mono float terbaru sejak pemanggilan terakhir (bisa kosong saat hening)
    cap.rate                   # sample rate (mis. 48000)
    cap.close()

Loopback = "rekam apa yang keluar ke speaker" (mode bersama, format campuran Windows, biasanya float32 stereo).
Saat tidak ada suara, Windows sering tidak mengirim paket sama sekali: read() kosong = hening.
Perangkat bawaan berganti (headset dicolok) dicek tiap 3 dtk lalu dibuka ulang.
"""
import array
import ctypes
import time
from ctypes import POINTER, byref, c_int64, c_long, c_uint32, c_uint64, c_void_p, c_wchar_p

ole32 = ctypes.OleDLL("ole32")
ole32.CoTaskMemFree.argtypes = [c_void_p]
ole32.CoTaskMemFree.restype = None


class GUID(ctypes.Structure):
    _fields_ = [("d1", c_uint32), ("d2", ctypes.c_uint16), ("d3", ctypes.c_uint16), ("d4", ctypes.c_ubyte * 8)]

    def __init__(self, s):
        super().__init__()
        h = s.replace("-", "")
        self.d1, self.d2, self.d3 = int(h[0:8], 16), int(h[8:12], 16), int(h[12:16], 16)
        for i in range(8):
            self.d4[i] = int(h[16 + i * 2:18 + i * 2], 16)


class WAVEFORMATEX(ctypes.Structure):
    _fields_ = [("wFormatTag", ctypes.c_uint16), ("nChannels", ctypes.c_uint16), ("nSamplesPerSec", c_uint32),
                ("nAvgBytesPerSec", c_uint32), ("nBlockAlign", ctypes.c_uint16), ("wBitsPerSample", ctypes.c_uint16),
                ("cbSize", ctypes.c_uint16)]


CLSID_MMDeviceEnumerator = GUID("BCDE0395-E52F-467C-8E3D-C4579291692E")
IID_IMMDeviceEnumerator = GUID("A95664D2-9614-4F35-A746-DE8DB63617E6")
IID_IAudioClient = GUID("1CB9AD4C-DBFA-4C32-B178-C2F568A703B2")
IID_IAudioCaptureClient = GUID("C8ADBD64-E71E-48A0-A4DE-185C395CD317")
CLSCTX_ALL = 0x17
E_RENDER, E_CONSOLE = 0, 0
SHAREMODE_SHARED = 0
STREAMFLAGS_LOOPBACK = 0x00020000
BUFFERFLAGS_SILENT = 0x2
WAVE_FORMAT_IEEE_FLOAT = 3
RPC_E_CHANGED_MODE = -2147417850


def _check(hr, what):
    if hr < 0:
        raise OSError("%s gagal (HRESULT 0x%08X)" % (what, hr & 0xFFFFFFFF))


def _call(obj, index, what, *args, argtypes=()):
    """Panggil method COM nomor `index` di vtable `obj` (HRESULT dicek)."""
    vtbl = ctypes.cast(obj, POINTER(POINTER(c_void_p))).contents
    fn = ctypes.WINFUNCTYPE(c_long, c_void_p, *argtypes)(vtbl[index])
    hr = fn(obj, *args)
    _check(hr, what)
    return hr


def _release(obj):
    if obj:
        vtbl = ctypes.cast(obj, POINTER(POINTER(c_void_p))).contents
        ctypes.WINFUNCTYPE(ctypes.c_ulong, c_void_p)(vtbl[2])(obj)


class LoopbackCapture:
    def __init__(self):
        self.rate = 48000
        self.channels = 2
        self.device_id = None
        self._enum = self._dev = self._client = self._capture = None
        self._float = True
        self._block = 8
        self._com = False
        self._checked = 0.0

    # ---------- buka / tutup ----------
    def open(self):
        if not self._com:
            hr = ole32.CoInitializeEx(None, 0)            # COINIT_MULTITHREADED, di thread pemanggil
            self._com = hr >= 0 or hr == RPC_E_CHANGED_MODE
        p = c_void_p()
        _check(ole32.CoCreateInstance(byref(CLSID_MMDeviceEnumerator), None, CLSCTX_ALL,
                                      byref(IID_IMMDeviceEnumerator), byref(p)), "CoCreateInstance")
        self._enum = p
        self._dev = self._default_device()
        self.device_id = self._device_id(self._dev)
        client = c_void_p()
        _call(self._dev, 3, "IMMDevice.Activate", byref(IID_IAudioClient), CLSCTX_ALL, None, byref(client),
              argtypes=(c_void_p, c_uint32, c_void_p, c_void_p))
        self._client = client
        fmt = POINTER(WAVEFORMATEX)()
        _call(client, 8, "GetMixFormat", byref(fmt), argtypes=(c_void_p,))
        try:
            f = fmt.contents
            self.rate, self.channels, self._block = f.nSamplesPerSec, f.nChannels, f.nBlockAlign
            # Mode bersama: format campuran hampir selalu float32 (tag 3, atau 0xFFFE extensible 32 bit)
            self._float = f.wFormatTag == WAVE_FORMAT_IEEE_FLOAT or (f.wFormatTag == 0xFFFE and f.wBitsPerSample == 32)
            if not self._float and f.wBitsPerSample != 16:
                raise OSError("format audio tidak didukung (%d bit, tag %#x)" % (f.wBitsPerSample, f.wFormatTag))
            # Buffer 200 ms (satuan 100 ns)
            _call(client, 3, "IAudioClient.Initialize", SHAREMODE_SHARED, STREAMFLAGS_LOOPBACK, c_int64(2000000),
                  c_int64(0), fmt, None, argtypes=(ctypes.c_int, c_uint32, c_int64, c_int64, c_void_p, c_void_p))
        finally:
            ole32.CoTaskMemFree(fmt)
        cap = c_void_p()
        _call(client, 14, "GetService", byref(IID_IAudioCaptureClient), byref(cap), argtypes=(c_void_p, c_void_p))
        self._capture = cap
        _call(client, 10, "IAudioClient.Start")
        self._checked = time.monotonic()

    def _default_device(self):
        dev = c_void_p()
        _call(self._enum, 4, "GetDefaultAudioEndpoint", E_RENDER, E_CONSOLE, byref(dev),
              argtypes=(ctypes.c_int, ctypes.c_int, c_void_p))
        return dev

    @staticmethod
    def _device_id(dev):
        sid = c_wchar_p()
        _call(dev, 5, "IMMDevice.GetId", byref(sid), argtypes=(c_void_p,))
        try:
            return sid.value
        finally:
            ole32.CoTaskMemFree(ctypes.cast(sid, c_void_p))

    def close(self):
        if self._client:
            try:
                _call(self._client, 11, "IAudioClient.Stop")
            except OSError:
                pass
        for name in ("_capture", "_client", "_dev", "_enum"):
            _release(getattr(self, name))
            setattr(self, name, None)

    def default_changed(self):
        """True kalau perangkat output bawaan Windows sudah berganti (cek paling sering tiap 3 dtk)."""
        now = time.monotonic()
        if now - self._checked < 3 or not self._enum:
            return False
        self._checked = now
        try:
            dev = self._default_device()
        except OSError:
            return False
        try:
            return self._device_id(dev) != self.device_id
        finally:
            _release(dev)

    # ---------- baca ----------
    def read(self):
        """Sampel mono baru (array float, -1..1). Kosong = tidak ada paket (hening). OSError = perangkat hilang."""
        out = array.array("f")
        cap = self._capture
        size = c_uint32()
        while True:
            _call(cap, 5, "GetNextPacketSize", byref(size), argtypes=(c_void_p,))
            if not size.value:
                break
            data, frames, flags = c_void_p(), c_uint32(), c_uint32()
            _call(cap, 3, "GetBuffer", byref(data), byref(frames), byref(flags), None, None,
                  argtypes=(c_void_p, c_void_p, c_void_p, c_void_p, c_void_p))
            n = frames.value
            if flags.value & BUFFERFLAGS_SILENT or not data.value:
                out.extend([0.0] * n)
            else:
                raw = ctypes.string_at(data.value, n * self._block)
                if self._float:
                    a = array.array("f", raw)
                else:
                    a = array.array("f", (v / 32768.0 for v in array.array("h", raw)))
                ch = self.channels
                if ch == 1:
                    out.extend(a)
                else:                                        # mono = rata-rata kiri + kanan
                    left, right = a[0::ch], a[1::ch]
                    out.extend(array.array("f", map(lambda x, y: (x + y) * 0.5, left, right)))
            _call(cap, 4, "ReleaseBuffer", n, argtypes=(c_uint32,))
        return out


if __name__ == "__main__":                 # uji cepat: level suara 5 dtk
    import math
    c = LoopbackCapture()
    c.open()
    print("perangkat:", c.device_id, "| %d Hz, %d kanal, %s" % (c.rate, c.channels, "float" if c._float else "int16"))
    end = time.time() + 5
    while time.time() < end:
        time.sleep(0.2)
        s = c.read()
        rms = math.sqrt(sum(v * v for v in s) / len(s)) if s else 0.0
        print("%5d sampel  level %s" % (len(s), "%.1f dBFS" % (20 * math.log10(rms)) if rms > 0 else "hening"))
    c.close()
