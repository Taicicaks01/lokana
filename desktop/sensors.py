"""Pembaca sensor PC untuk Lokana Desktop (Windows).

Sumber:
- psutil: CPU %, RAM %, jaringan (unduh/unggah), disk (baca+tulis), baterai laptop.
- nvidia-smi: suhu & pemakaian GPU NVIDIA (ikut driver NVIDIA, tanpa program lain).
- Suhu CPU: LibreHardwareMonitor bila berjalan (paling presisi, web server bawaannya port 8085), kalau tidak
  zona termal ACPI dari penghitung kinerja Windows (bawaan, tanpa admin; di laptop mengikuti suhu CPU).

Setiap metrik punya ID tetap (dipakai di config.json "metrics"). Hasil kirim: daftar (kind, label, value, unit)
sesuai PC_STATS (kind 0 angka, 1 persen, 2 suhu). Tidak ada angka palsu: sensor yang tidak tersedia dilewati.
"""
import json
import shutil
import subprocess
import sys
import time
import urllib.request

import psutil

CREATE_NO_WINDOW = 0x08000000 if sys.platform == "win32" else 0
LHM_URL = "http://127.0.0.1:8085/data.json"

# (id, nama di jendela pengaturan, kind PC_STATS, label OLED maks 6 huruf). Urutan = urutan bawaan.
METRICS = [
    ("cpu", "CPU %", 1, "CPU"),
    ("ram", "RAM %", 1, "RAM"),
    ("cpu_temp", "Suhu CPU", 2, "CPU"),
    ("gpu_temp", "Suhu GPU", 2, "GPU"),
    ("gpu", "Pemakaian GPU", 1, "GPU"),
    ("down", "Unduh (jaringan)", 0, "Unduh"),
    ("up", "Unggah (jaringan)", 0, "Unggah"),
    ("disk", "Disk baca + tulis", 0, "Disk"),
    ("battery", "Baterai laptop", 1, "Batre"),
]
IDS = [m[0] for m in METRICS]
NAMES = {m[0]: m[1] for m in METRICS}
MAX_METRICS = 12

# Template cepat di jendela pengaturan (urutan = urutan tampil)
TEMPLATES = {
    "Ringkas": ["cpu", "ram", "cpu_temp", "gpu_temp"],
    "Gamer": ["gpu_temp", "gpu", "cpu_temp", "cpu", "ram"],
    "Jaringan": ["down", "up", "disk", "cpu"],
    "Laptop": ["battery", "cpu", "ram", "cpu_temp"],
    "Semua": list(IDS),
}

REASONS = {                       # singkat: tampil di samping nama metrik yang tidak tersedia
    "cpu_temp": "tidak ada sensor; pasang LibreHardwareMonitor",
    "gpu_temp": "butuh GPU NVIDIA",
    "gpu": "butuh GPU NVIDIA",
    "battery": "PC tanpa baterai",
}


class ThermalZone:
    """Suhu zona termal ACPI lewat penghitung kinerja Windows (PDH), tanpa admin & tanpa program lain.

    Di laptop (diuji: Ryzen 5 7535HS, zona TZ01) zona ini mengikuti suhu CPU/APU: diam ±50 °C, beban penuh ±61 °C,
    resolusi ±1 °C. Dipakai sebagai suhu CPU bila LibreHardwareMonitor tidak berjalan. PC desktop sering tidak punya
    zona termal ACPI -> None.
    """
    PDH_FMT_DOUBLE = 0x00000200
    PDH_MORE_DATA = 0x800007D2
    PATHS = (("\\Thermal Zone Information(*)\\High Precision Temperature", 10.0),   # 0,1 kelvin
             ("\\Thermal Zone Information(*)\\Temperature", 1.0))                   # kelvin (Windows lama)

    def __init__(self):
        self.ok = False
        if sys.platform != "win32":
            return
        import ctypes
        from ctypes import wintypes as wt
        self._c, self._wt = ctypes, wt

        class Value(ctypes.Structure):
            _fields_ = [("CStatus", wt.DWORD), ("doubleValue", ctypes.c_double)]   # union PDH_FMT_COUNTERVALUE

        class Item(ctypes.Structure):
            _fields_ = [("szName", wt.LPWSTR), ("FmtValue", Value)]

        self._Item = Item
        self._pdh = pdh = ctypes.windll.pdh
        H, P = ctypes.c_void_p, ctypes.POINTER
        pdh.PdhOpenQueryW.argtypes = [wt.LPCWSTR, ctypes.c_size_t, P(H)]
        pdh.PdhAddEnglishCounterW.argtypes = [H, wt.LPCWSTR, ctypes.c_size_t, P(H)]
        pdh.PdhCollectQueryData.argtypes = [H]
        pdh.PdhGetFormattedCounterArrayW.argtypes = [H, wt.DWORD, P(wt.DWORD), P(wt.DWORD), ctypes.c_void_p]
        for f in (pdh.PdhOpenQueryW, pdh.PdhAddEnglishCounterW, pdh.PdhCollectQueryData, pdh.PdhGetFormattedCounterArrayW):
            f.restype = wt.DWORD                            # PDH_STATUS sebagai unsigned (0x800007D2 = PDH_MORE_DATA)
        self._q = ctypes.c_void_p()
        if self._pdh.PdhOpenQueryW(None, 0, ctypes.byref(self._q)) != 0:
            return
        for path, div in self.PATHS:
            h = ctypes.c_void_p()
            if self._pdh.PdhAddEnglishCounterW(self._q, path, 0, ctypes.byref(h)) == 0 and self._sample(h, div) is not None:
                self._h, self._div, self.ok = h, div, True
                return

    def _sample(self, h, div):
        c, wt = self._c, self._wt
        if self._pdh.PdhCollectQueryData(self._q) != 0:
            return None
        size, count = wt.DWORD(0), wt.DWORD(0)
        r = self._pdh.PdhGetFormattedCounterArrayW(h, self.PDH_FMT_DOUBLE, c.byref(size), c.byref(count), None)
        if r != self.PDH_MORE_DATA or not count.value:
            return None
        # Buffer = larik item + nama zona (string) di belakangnya: harus sebesar `size` byte dari PDH
        raw = c.create_string_buffer(size.value)
        if self._pdh.PdhGetFormattedCounterArrayW(h, self.PDH_FMT_DOUBLE, c.byref(size), c.byref(count), raw) != 0:
            return None
        items = c.cast(raw, c.POINTER(self._Item))
        temps = [items[i].FmtValue.doubleValue / div - 273.15 for i in range(count.value)
                 if items[i].FmtValue.CStatus in (0, 1)]
        temps = [t for t in temps if 0 < t < 125]          # buang nilai mustahil (zona mati = 0 K)
        return max(temps) if temps else None

    def read(self):
        if not self.ok:
            return None
        try:
            return self._sample(self._h, self._div)
        except Exception:
            return None


def _speed(bytes_per_s):
    """Kecepatan -> (nilai, satuan): KB/s di bawah 1 MB/s."""
    mb = bytes_per_s / (1024 * 1024)
    return (mb, "MB/s") if mb >= 1 else (bytes_per_s / 1024, "KB/s")


def select(values, order):
    """Metrik terpilih yang tersedia, sesuai urutan config, maks 12 -> daftar PC_STATS."""
    out = [values[i] for i in order if i in values and values[i] is not None]
    return out[:MAX_METRICS]


class Sensors:
    def __init__(self):
        psutil.cpu_percent(interval=None)                 # panggilan pertama selalu 0
        self._net = psutil.net_io_counters()
        self._disk = psutil.disk_io_counters()
        self._t = time.monotonic()
        self._nvsmi = shutil.which("nvidia-smi")
        self._gpu = None                                   # (suhu, pemakaian)
        self._gpu_at = 0.0
        self._lhm_cpu = None
        self._lhm_at = 0.0
        self._lhm_fail_at = 0.0
        self._tz = ThermalZone()
        self.cpu_temp_source = None                        # "LibreHardwareMonitor" / "zona termal Windows" / None

    # ---------- NVIDIA ----------
    def _read_gpu(self):
        if not self._nvsmi:
            return None
        now = time.monotonic()
        if now - self._gpu_at < 3:                          # nvidia-smi butuh ±100 ms: cukup tiap 3 dtk
            return self._gpu
        self._gpu_at = now
        try:
            out = subprocess.run(
                [self._nvsmi, "--query-gpu=temperature.gpu,utilization.gpu", "--format=csv,noheader,nounits"],
                capture_output=True, text=True, timeout=3, creationflags=CREATE_NO_WINDOW).stdout
            temp, util = (float(x) for x in out.strip().splitlines()[0].split(","))
            self._gpu = (temp, util)
        except Exception:
            self._gpu = None
        return self._gpu

    # ---------- LibreHardwareMonitor (suhu CPU) ----------
    def _read_lhm_cpu(self):
        now = time.monotonic()
        if now - self._lhm_fail_at < 30:                    # tidak berjalan: coba lagi 30 dtk kemudian
            return None
        if now - self._lhm_at < 3:
            return self._lhm_cpu
        self._lhm_at = now
        try:
            with urllib.request.urlopen(LHM_URL, timeout=1) as r:
                tree = json.load(r)
        except Exception:
            self._lhm_fail_at = now
            self._lhm_cpu = None
            return None
        temps = []

        def walk(node, cpu):
            sid = str(node.get("SensorId", ""))
            cpu = cpu or sid.startswith(("/amdcpu", "/intelcpu"))
            if cpu and "/temperature/" in sid:
                try:
                    temps.append(float(str(node.get("Value", "")).split()[0].replace(",", ".")))
                except ValueError:
                    pass
            for ch in node.get("Children", []):
                walk(ch, cpu)

        walk(tree, False)
        self._lhm_cpu = max(temps) if temps else None      # Tctl/Tdie / Package = yang tertinggi
        return self._lhm_cpu

    # ---------- Semua metrik ----------
    def read_all(self):
        """{id: (kind, label, value, unit)} untuk semua metrik; None = tidak tersedia di PC ini."""
        now = time.monotonic()
        dt = max(now - self._t, 0.1)
        net, disk = psutil.net_io_counters(), psutil.disk_io_counters()
        down = (net.bytes_recv - self._net.bytes_recv) / dt
        up = (net.bytes_sent - self._net.bytes_sent) / dt
        dsk = ((disk.read_bytes - self._disk.read_bytes) + (disk.write_bytes - self._disk.write_bytes)) / dt \
            if disk and self._disk else 0
        self._net, self._disk, self._t = net, disk, now

        v = {i: None for i in IDS}
        v["cpu"] = (1, "CPU", psutil.cpu_percent(interval=None), "%")
        v["ram"] = (1, "RAM", psutil.virtual_memory().percent, "%")
        cpu_t = self._read_lhm_cpu()                       # paling presisi (Tctl/Tdie), kalau LHM berjalan
        self.cpu_temp_source = "LibreHardwareMonitor" if cpu_t is not None else None
        if cpu_t is None:
            cpu_t = self._tz.read()                        # bawaan Windows, tanpa admin
            self.cpu_temp_source = "zona termal Windows" if cpu_t is not None else None
        if cpu_t is not None:
            v["cpu_temp"] = (2, "CPU", cpu_t, "C")
        gpu = self._read_gpu()
        if gpu:
            v["gpu_temp"] = (2, "GPU", gpu[0], "C")
            v["gpu"] = (1, "GPU", gpu[1], "%")
        for key, label, bps in (("down", "Unduh", down), ("up", "Unggah", up), ("disk", "Disk", dsk)):
            val, unit = _speed(max(bps, 0))
            v[key] = (0, label, val, unit)
        bat = psutil.sensors_battery()
        if bat is not None:
            v["battery"] = (1, "Batre+" if bat.power_plugged else "Batre", bat.percent, "%")
        return v

    def read(self, order=None):
        """Daftar PC_STATS untuk metrik terpilih (bawaan: semua, urutan bawaan)."""
        return select(self.read_all(), order or IDS)
