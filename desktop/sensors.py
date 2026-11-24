"""Pembaca sensor PC untuk Lokana Desktop (Windows).

Sumber:
- psutil: CPU %, RAM %, jaringan (unduh/unggah), disk (baca+tulis), baterai laptop.
- nvidia-smi: suhu & pemakaian GPU NVIDIA (ikut driver NVIDIA, tanpa program lain).
- LibreHardwareMonitor (opsional): suhu CPU, dibaca dari web server bawaannya
  (Options -> Remote Web Server -> Run, port 8085). Tanpa itu suhu CPU tidak ditampilkan.

Hasil: daftar (kind, label, value, unit) sesuai PC_STATS (kind 0 angka, 1 persen, 2 suhu).
Tidak ada angka palsu: sensor yang tidak tersedia dilewati.
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


def _speed(bytes_per_s):
    """Kecepatan -> (nilai, satuan): KB/s di bawah 1 MB/s."""
    mb = bytes_per_s / (1024 * 1024)
    return (mb, "MB/s") if mb >= 1 else (bytes_per_s / 1024, "KB/s")


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
    def read(self):
        now = time.monotonic()
        dt = max(now - self._t, 0.1)
        net, disk = psutil.net_io_counters(), psutil.disk_io_counters()
        down = (net.bytes_recv - self._net.bytes_recv) / dt
        up = (net.bytes_sent - self._net.bytes_sent) / dt
        dsk = ((disk.read_bytes - self._disk.read_bytes) + (disk.write_bytes - self._disk.write_bytes)) / dt \
            if disk and self._disk else 0
        self._net, self._disk, self._t = net, disk, now

        m = [(1, "CPU", psutil.cpu_percent(interval=None), "%"),
             (1, "RAM", psutil.virtual_memory().percent, "%")]
        cpu_t = self._read_lhm_cpu()
        if cpu_t is not None:
            m.append((2, "CPU", cpu_t, "C"))
        gpu = self._read_gpu()
        if gpu:
            m.append((2, "GPU", gpu[0], "C"))
            m.append((1, "GPU", gpu[1], "%"))
        for label, v in (("Unduh", down), ("Unggah", up), ("Disk", dsk)):
            val, unit = _speed(max(v, 0))
            m.append((0, label, val, unit))
        bat = psutil.sensors_battery()
        if bat is not None:
            m.append((1, "Batre+" if bat.power_plugged else "Batre", bat.percent, "%"))
        return m[:12]

    def sources(self):
        """Ringkasan sumber yang aktif (untuk menu tray / log)."""
        return {"nvidia-smi": bool(self._nvsmi and self._gpu), "LibreHardwareMonitor": self._lhm_cpu is not None,
                "baterai": psutil.sensors_battery() is not None}
