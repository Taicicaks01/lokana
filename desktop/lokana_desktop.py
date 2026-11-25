"""Lokana Desktop — monitor PC di layar Lokana lewat USB (Windows).

Ikon di system tray. Mencari Lokana di port USB, menyinkronkan jam, lalu mengirim metrik PC
(CPU, RAM, suhu, jaringan, disk, baterai laptop) tiap 2 detik sebagai PC_STATS.
Menu tray "Pengaturan..." (atau klik ganda ikon) membuka jendela pratinjau OLED + pilihan metrik (v0.8).
Visualizer audio (v0.8): suara yang diputar PC (WASAPI loopback) dikirim sebagai AUDIO_BANDS ±25 fps selama ada suara.

  python lokana_desktop.py               # tray
  python lokana_desktop.py --no-tray     # tanpa tray, cetak metrik ke terminal (uji)
  python lokana_desktop.py --port COM10  # paksa port

Pengaturan: %APPDATA%\\LokanaDesktop\\config.json
            {"port": null, "exclude": ["COM7"], "interval": 2, "metrics": ["cpu", "ram", ...],
             "labels": {"cpu": "Prosesor"}, "decimals": {"down": 2}, "pairs": ["cpu"], "decimal_sep": ",",  (layout.py)
             "audio": {"enabled": true, "bands": 32, "style": 0}}                                       (visualizer)
Log:        %APPDATA%\\LokanaDesktop\\log.txt
"""
import argparse
import json
import os
import sys
import threading
import time

VERSION = "0.8.0-dev"
APP = "LokanaDesktop"
CFG_DIR = os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")), APP)
CFG_FILE = os.path.join(CFG_DIR, "config.json")
LOG_FILE = os.path.join(CFG_DIR, "log.txt")
RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"

os.makedirs(CFG_DIR, exist_ok=True)


def log(msg):
    line = time.strftime("%Y-%m-%d %H:%M:%S ") + msg
    if sys.stdout:                      # .exe tanpa konsol: sys.stdout = None
        try:
            print(line)
        except UnicodeEncodeError:      # konsol cp1252 & nama Lokana Dewanagari: jangan sampai log menggagalkan koneksi
            enc = sys.stdout.encoding or "ascii"
            print(line.encode(enc, "replace").decode(enc))
    try:
        if os.path.exists(LOG_FILE) and os.path.getsize(LOG_FILE) > 512 * 1024:
            os.replace(LOG_FILE, LOG_FILE + ".1")
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass


def load_cfg():
    from sensors import IDS
    cfg = {"port": None, "exclude": [], "interval": 2, "metrics": list(IDS),
           "labels": {}, "decimals": {}, "pairs": [], "decimal_sep": ",",       # 0.8: lihat layout.py
           "audio": {"enabled": True, "bands": 32, "style": 0}}
    try:
        with open(CFG_FILE, encoding="utf-8") as f:
            cfg.update(json.load(f))
    except (OSError, ValueError):
        save_cfg(cfg)
    cfg["metrics"] = [m for m in cfg.get("metrics", IDS) if m in IDS]      # ID lama/salah dibuang
    return cfg


def save_cfg(cfg):
    try:
        tmp = CFG_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2)
        os.replace(tmp, CFG_FILE)                    # atomik: config tidak rusak kalau PC mati saat menyimpan
    except OSError as e:
        log(f"gagal menyimpan pengaturan: {e}")


def resource(name):
    """Berkas yang ikut dibungkus PyInstaller (sys._MEIPASS) atau di samping skrip."""
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base, name)


# ---------------- Mulai bersama Windows (HKCU\...\Run) ----------------
def _exe_cmd():
    if getattr(sys, "frozen", False):
        return f'"{sys.executable}"'
    return f'"{sys.executable.replace("python.exe", "pythonw.exe")}" "{os.path.abspath(__file__)}"'


def autostart_get():
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as k:
            winreg.QueryValueEx(k, APP)
            return True
    except OSError:
        return False


def autostart_set(on):
    import winreg
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0, winreg.KEY_SET_VALUE) as k:
        if on:
            winreg.SetValueEx(k, APP, 0, winreg.REG_SZ, _exe_cmd())
        else:
            try:
                winreg.DeleteValue(k, APP)
            except OSError:
                pass


# ---------------- Pekerja: baca sensor, cari Lokana, kirim metrik ----------------
class Worker(threading.Thread):
    """Membaca sensor tiap interval (juga saat Lokana belum tersambung, untuk pratinjau), mencoba menyambung
    tiap 5 dtk, dan mengirim PC_STATS. `kick` = kirim sekarang (pengaturan berubah)."""

    def __init__(self, cfg, port=None, verbose=False, on_change=None):
        super().__init__(daemon=True)
        from link_usb import LokanaUsb
        from sensors import Sensors
        self.cfg = cfg
        self.usb = LokanaUsb(f"Lokana Desktop {VERSION}", port or cfg.get("port"), cfg.get("exclude", []), log)
        self.sensors = Sensors()
        self.verbose = verbose
        self.on_change = on_change or (lambda: None)
        self.paused = False
        self.stop_ev = threading.Event()
        self.kick = threading.Event()
        self.status = "Mencari Lokana..."
        self.values = {}          # {id: (kind, label, value, unit) | None} semua metrik, untuk jendela pengaturan
        self.last = []            # PC_STATS terakhir yang dikirim / akan dikirim
        self.layout = ([], [], [], [])   # (ids, metrics, texts, rows) dari layout.build()
        self.legacy = False       # Lokana tersambung tapi belum 0.8 (tanpa STATS_LAYOUT): pratinjau gaya lama
        self.link_ok = False      # Lokana terkonfirmasi (bukan port lain yang sedang dicoba saat mencari)
        self.audio = None         # AudioWorker (visualizer), diisi pemanggil

    def _set(self, status):
        if status != self.status:
            self.status = status
            self.on_change()

    def _connect(self):
        self.link_ok = False
        self._set("Mencari Lokana...")
        try:
            found = self.usb.connect()
        except Exception as e:                           # port hilang di tengah pencarian, dll.
            log(f"gagal mencari: {e}")
            found = False
        if not found:
            return False
        if not self.usb.supports_stats():
            log("Lokana OS di perangkat ini belum mendukung Monitor PC (perlu 0.7.0)")
            self._set(f"Perbarui Lokana OS ke 0.7 ({self.usb.port})")
            self.usb.close()
            return False
        self.legacy = not self.usb.supports_layout()
        if self.legacy:
            log("Lokana OS di perangkat ini belum 0.8: label sendiri & dua metrik per baris belum tampil")
        self._set(f"Tersambung: {self.usb.info.get('device_name')} ({self.usb.port})")
        self.link_ok = True
        return True

    def run(self):
        from layout import build
        synced_at = 0.0
        next_try = 0.0
        while not self.stop_ev.is_set():
            if not self.usb.connected and time.monotonic() >= next_try:
                if self._connect():
                    synced_at = 0.0
                else:
                    next_try = time.monotonic() + (30 if "Perbarui" in self.status else 5)
            try:
                self.values = self.sensors.read_all()
                self.layout = build(self.values, self.cfg)
                self.last = self.layout[1]
            except Exception as e:
                log(f"sensor gagal dibaca: {e}")
            if self.usb.connected:
                try:
                    if time.time() - synced_at > 3600:       # jam Lokana ikut PC, ulang tiap jam
                        self.usb.sync_time()
                        synced_at = time.time()
                    if not self.paused:
                        _ids, metrics, texts, rows = self.layout
                        self.usb.send_stats(metrics, texts, rows)
                except Exception as e:                       # kabel dicabut, Lokana restart
                    log(f"koneksi putus: {e.__class__.__name__}")
                    self.link_ok = False
                    self.usb.close()
                    next_try = 0.0
                    continue
            if self.verbose:
                print("  " + " | ".join(f"{l} {v:.1f}{u}" for _k, l, v, u in self.last))
            interval = max(1.0, float(self.cfg.get("interval", 2)))
            self.kick.wait(interval)
            self.kick.clear()
        self.link_ok = False
        self.usb.close()


class AudioWorker(threading.Thread):
    """Visualizer (v0.8): tangkap suara PC (WASAPI loopback), kirim AUDIO_BANDS ±25 fps selama ada suara.
    Hening HANG_S dtk -> berhenti mengirim; Lokana kembali ke modul sebelumnya 1,5 dtk kemudian.
    Saat hening hanya level suara yang dihitung (tanpa FFT), jadi hampir tanpa beban CPU."""
    FPS = 25
    HANG_S = 10

    def __init__(self, worker, cfg):
        super().__init__(daemon=True)
        self.worker, self.cfg = worker, cfg
        self.bands = []           # pita terakhir (pratinjau di jendela pengaturan); kosong = tidak aktif
        self.sending = False      # sedang dikirim ke Lokana
        self.status = "Mati"

    def _opts(self):
        a = self.cfg.get("audio") or {}
        nb = a.get("bands", 32)
        return bool(a.get("enabled", True)), nb if nb in (16, 32) else 32, 1 if a.get("style") == 1 else 0

    def run(self):
        from audio_capture import LoopbackCapture
        from spectrum import Spectrum
        cap = sp = None
        retry_at = last_sound = 0.0
        prev = time.monotonic()
        while not self.worker.stop_ev.is_set():
            t0 = time.monotonic()
            enabled, nb, style = self._opts()
            if not enabled:
                if cap:
                    cap.close()
                    cap = None
                self.bands, self.sending, self.status = [], False, "Mati"
                time.sleep(0.5)
                continue
            if cap is None:
                if t0 < retry_at:
                    time.sleep(0.5)
                    continue
                try:
                    cap = LoopbackCapture()
                    cap.open()
                    sp = Spectrum(nb, cap.rate)
                    log(f"visualizer: menangkap suara ({cap.rate} Hz, {cap.channels} kanal)")
                except Exception as e:
                    log(f"visualizer: tidak bisa menangkap suara ({e})")
                    self.status = "Tidak bisa menangkap suara PC"
                    cap = None
                    retry_at = t0 + 10
                    continue
            try:
                if cap.default_changed():
                    raise OSError("perangkat output bawaan berganti")
                samples = cap.read()
            except OSError as e:
                log(f"visualizer: buka ulang ({e})")
                cap.close()
                cap = None
                continue
            sp.set_bands(nb)
            sp.push(samples)
            now = time.monotonic()
            dt, prev = now - prev, now
            if samples and not sp.silent:
                last_sound = now
            if now - last_sound < self.HANG_S:
                self.bands = sp.compute(dt) if samples else sp.decay()
                ok = self.worker.link_ok and not self.worker.paused and self.worker.usb.supports_audio()
                if ok:
                    try:
                        self.worker.usb.send_audio(self.bands, style)
                    except Exception:
                        ok = False            # sambung ulang diurus pekerja sensor
                self.sending = ok
                self.status = "Ada suara: dikirim ke Lokana" if ok else "Ada suara"
            else:
                self.bands, self.sending, self.status = [], False, "Hening"
            time.sleep(max(0.0, 1.0 / self.FPS - (time.monotonic() - t0)))
        if cap:
            cap.close()


# ---------------- Tray + jendela pengaturan ----------------
def run_tray(cfg, port, open_settings=False):
    """tkinter memegang thread utama (wajib satu thread); ikon tray berjalan terpisah (run_detached).
    Perintah dari menu tray dititipkan lewat antrian dan diproses di thread tkinter."""
    import ctypes
    import queue
    import tkinter as tk

    import pystray
    from PIL import Image

    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(1)   # jendela tajam di layar ber-skala (125%, 150%)
    except Exception:
        pass
    root = tk.Tk()
    root.withdraw()
    q = queue.Queue()
    icon = None

    def refresh():
        if icon:
            icon.title = f"Lokana Desktop - {worker.status}"
            icon.update_menu()

    worker = Worker(cfg, port, on_change=refresh)
    worker.audio = AudioWorker(worker, cfg)

    def toggle_pause(_i, _item):
        worker.paused = not worker.paused
        log("jeda" if worker.paused else "lanjut")
        refresh()

    def toggle_auto(_i, _item):
        autostart_set(not autostart_get())
        refresh()

    menu = pystray.Menu(
        pystray.MenuItem(lambda _i: worker.status, None, enabled=False),
        pystray.MenuItem("Pengaturan...", lambda _i, _it: q.put("settings"), default=True),
        pystray.MenuItem("Jeda kirim data", toggle_pause, checked=lambda _i: worker.paused),
        pystray.MenuItem("Jalankan saat Windows mulai", toggle_auto, checked=lambda _i: autostart_get()),
        pystray.MenuItem("Buka folder log", lambda _i, _it: os.startfile(CFG_DIR)),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Keluar", lambda _i, _it: q.put("quit")),
    )
    icon = pystray.Icon(APP, Image.open(resource("icon.png")), f"Lokana Desktop {VERSION}", menu)

    def poll():
        while not q.empty():
            cmd = q.get()
            if cmd == "settings":
                from settings_window import SettingsWindow
                SettingsWindow.show(root, worker, cfg, lambda: save_cfg(cfg), resource("icon.png"))
            elif cmd == "quit":
                worker.stop_ev.set()
                worker.kick.set()
                icon.stop()
                root.destroy()
                return
        root.after(150, poll)

    worker.start()
    worker.audio.start()
    icon.run_detached()
    if open_settings:
        q.put("settings")
    root.after(150, poll)
    root.mainloop()


def main():
    ap = argparse.ArgumentParser(description=f"Lokana Desktop {VERSION}: monitor PC di Lokana lewat USB")
    ap.add_argument("--port", help="paksa port, contoh COM10")
    ap.add_argument("--no-tray", action="store_true", help="tanpa ikon tray; cetak metrik ke terminal")
    ap.add_argument("--seconds", type=float, default=0, help="--no-tray: berhenti setelah N detik (uji)")
    ap.add_argument("--settings", action="store_true", help="buka jendela pengaturan saat mulai")
    a = ap.parse_args()
    cfg = load_cfg()
    log(f"Lokana Desktop {VERSION} mulai")
    if a.no_tray:
        w = Worker(cfg, a.port, verbose=True)
        w.audio = AudioWorker(w, cfg)
        w.start()
        w.audio.start()
        try:
            end = time.time() + a.seconds if a.seconds else None
            while w.is_alive() and (end is None or time.time() < end):
                time.sleep(0.5)
        except KeyboardInterrupt:
            pass
        w.stop_ev.set()
        w.join(3)
        return
    run_tray(cfg, a.port, open_settings=a.settings)


if __name__ == "__main__":
    main()
