"""Jendela pengaturan Lokana Desktop (v0.8 langkah 1): pratinjau OLED 1:1 + pilih & urutkan metrik.

tkinter bawaan Python (tanpa dependensi GUI tambahan). Semua perubahan langsung berlaku dan disimpan ke
config Desktop (bukan firmware). Pratinjau dirender oleh oled_preview.py, sama persis dengan modul Monitor.
"""
import time
import tkinter as tk
from tkinter import ttk

from PIL import ImageTk

import oled_preview
from sensors import IDS, MAX_METRICS, NAMES, REASONS, TEMPLATES, select

PAGE_MS = 5000          # sama dengan modul Monitor: halaman berganti sendiri tiap 5 dtk
SCALE = 4


def _pretty(m):
    """Nilai untuk daftar metrik (lebih mudah dibaca daripada format OLED)."""
    kind, _label, value, unit = m
    if kind == 2:
        return "%.0f °C" % value
    if kind == 1:
        return "%.0f%%" % value
    return "%.1f %s" % (value, unit)


class SettingsWindow:
    _open = None

    @classmethod
    def show(cls, root, worker, cfg, save, icon_path=None):
        if cls._open and cls._open.win.winfo_exists():
            cls._open.win.deiconify()
            cls._open.win.lift()
            cls._open.win.focus_force()
            return
        cls._open = cls(root, worker, cfg, save, icon_path)

    def __init__(self, root, worker, cfg, save, icon_path):
        self.worker, self.cfg, self.save = worker, cfg, save
        self.win = tk.Toplevel(root)
        self.win.title("Lokana Desktop — Pengaturan")
        self.win.resizable(False, False)
        if icon_path:
            try:
                self._icon = tk.PhotoImage(file=icon_path)
                self.win.iconphoto(False, self._icon)
            except tk.TclError:
                pass
        sel = [i for i in cfg.get("metrics", IDS) if i in IDS]
        self.order = sel + [i for i in IDS if i not in sel]      # terpilih dulu, lalu sisanya
        self.selected = set(sel)
        self.page = 0
        self.page_at = time.monotonic()
        self.msg_until = 0.0
        self._build()
        self._rebuild_list()
        self._tick()

    # ---------------- tata letak ----------------
    def _build(self):
        pad = {"padx": 12, "pady": 6}
        top = ttk.Frame(self.win)
        top.grid(row=0, column=0, columnspan=2, sticky="we", **pad)
        self.status = ttk.Label(top, text="")
        self.status.pack(side="left")
        ttk.Label(top, text="dtk").pack(side="right")
        self.interval = tk.IntVar(value=int(self.cfg.get("interval", 2)))
        sp = ttk.Spinbox(top, from_=1, to=10, width=3, textvariable=self.interval, command=self._interval_changed)
        sp.pack(side="right", padx=4)
        sp.bind("<FocusOut>", lambda _e: self._interval_changed())
        ttk.Label(top, text="Kirim tiap").pack(side="right")

        left = ttk.Frame(self.win)
        left.grid(row=1, column=0, sticky="n", **pad)
        bezel = tk.Frame(left, bg="#24202A", padx=10, pady=10)
        bezel.pack()
        self.preview = tk.Label(bezel, bg="#000000", bd=0)
        self.preview.pack()
        nav = ttk.Frame(left)
        nav.pack(pady=(8, 0))
        ttk.Button(nav, text="◀", width=3, command=lambda: self._flip(-1)).pack(side="left")
        self.page_lbl = ttk.Label(nav, text="", width=14, anchor="center")
        self.page_lbl.pack(side="left", padx=6)
        ttk.Button(nav, text="▶", width=3, command=lambda: self._flip(1)).pack(side="left")
        ttk.Label(left, text="Pratinjau 1:1 layar Monitor Lokana (128×64, diperbesar 4×)",
                  foreground="#6b6170").pack(pady=(6, 0))

        right = ttk.Frame(self.win)
        right.grid(row=1, column=1, sticky="n", **pad)
        ttk.Label(right, text="Metrik yang tampil (maks %d, 4 per halaman)" % MAX_METRICS,
                  font=("Segoe UI", 10, "bold")).pack(anchor="w")
        self.list = ttk.Frame(right)
        self.list.pack(anchor="w", fill="x", pady=(4, 0))
        self.msg = ttk.Label(right, text="", foreground="#B4630F")
        self.msg.pack(anchor="w", pady=(4, 0))

        tpl = ttk.Frame(self.win)
        tpl.grid(row=2, column=0, columnspan=2, sticky="we", padx=12, pady=(4, 12))
        ttk.Label(tpl, text="Template cepat:").pack(side="left")
        for name in TEMPLATES:
            ttk.Button(tpl, text=name, command=lambda n=name: self._template(n)).pack(side="left", padx=3)

    def _rebuild_list(self):
        for w in self.list.winfo_children():
            w.destroy()
        values = self.worker.values or {}
        self.value_lbls = {}
        shown = 0                                     # metrik terpilih yang tersedia (untuk pemisah halaman)
        header_unsel = False
        for idx, mid in enumerate(self.order):
            on = mid in self.selected
            avail = values.get(mid) is not None
            if on and avail and shown % 4 == 0:
                ttk.Label(self.list, text="── Halaman %d " % (shown // 4 + 1) + "─" * 20,
                          foreground="#C4386F").grid(row=idx * 2, column=0, columnspan=5, sticky="w", pady=(6, 0))
            if not on and not header_unsel:
                header_unsel = True
                ttk.Label(self.list, text="── Tidak ditampilkan " + "─" * 14,
                          foreground="#6b6170").grid(row=idx * 2, column=0, columnspan=5, sticky="w", pady=(6, 0))
            var = tk.BooleanVar(value=on)
            ttk.Checkbutton(self.list, variable=var, command=lambda m=mid, v=var: self._toggle(m, v)).grid(
                row=idx * 2 + 1, column=0, sticky="w")
            src = getattr(getattr(self.worker, "sensors", None), "cpu_temp_source", None) if mid == "cpu_temp" else None
            name = NAMES[mid] + ("  · " + src if (avail and src) else "") +                 ("" if avail else "  (" + REASONS.get(mid, "tidak tersedia") + ")")
            ttk.Label(self.list, text=name, width=44,
                      foreground="#1B1720" if avail else "#9a8f9e").grid(row=idx * 2 + 1, column=1, sticky="w")
            lbl = ttk.Label(self.list, text="", width=11, anchor="e")
            lbl.grid(row=idx * 2 + 1, column=2, sticky="e")
            self.value_lbls[mid] = lbl
            if on:
                ttk.Button(self.list, text="↑", width=3, command=lambda m=mid: self._move(m, -1)).grid(
                    row=idx * 2 + 1, column=3, padx=(6, 0))
                ttk.Button(self.list, text="↓", width=3, command=lambda m=mid: self._move(m, 1)).grid(
                    row=idx * 2 + 1, column=4)
            if on and avail:
                shown += 1
        self._avail_key = tuple(values.get(i) is not None for i in IDS)

    # ---------------- aksi ----------------
    def _commit(self):
        self.cfg["metrics"] = [i for i in self.order if i in self.selected]
        self.save()
        self.worker.kick.set()                        # kirim ke Lokana sekarang, tidak menunggu interval

    def _say(self, text):
        self.msg.config(text=text)
        self.msg_until = time.monotonic() + 4

    def _toggle(self, mid, var):
        if var.get():
            if len(self.selected) >= MAX_METRICS:
                var.set(False)
                self._say("Maksimal %d metrik." % MAX_METRICS)
                return
            self.selected.add(mid)
            # pindah ke akhir kelompok terpilih
            self.order.remove(mid)
            self.order.insert(len([i for i in self.order if i in self.selected]), mid)
        else:
            self.selected.discard(mid)
            self.order.remove(mid)
            self.order.append(mid)
        self._commit()
        self._rebuild_list()
        self._render()

    def _move(self, mid, step):
        sel = [i for i in self.order if i in self.selected]
        i = sel.index(mid)
        j = i + step
        if 0 <= j < len(sel):
            sel[i], sel[j] = sel[j], sel[i]
            self.order = sel + [m for m in self.order if m not in self.selected]
            self._commit()
            self._rebuild_list()
            self._render()

    def _template(self, name):
        ids = TEMPLATES[name][:MAX_METRICS]
        self.selected = set(ids)
        self.order = list(ids) + [i for i in IDS if i not in ids]
        self.page = 0
        self.page_at = time.monotonic()
        self._commit()
        self._rebuild_list()
        self._render()
        self._say("Template %s dipakai." % name)

    def _interval_changed(self):
        try:
            v = max(1, min(10, int(self.interval.get())))
        except (tk.TclError, ValueError):
            v = int(self.cfg.get("interval", 2))
        self.interval.set(v)
        if v != self.cfg.get("interval"):
            self.cfg["interval"] = v
            self.save()

    def _flip(self, step):
        n = len(self._metrics())
        self.page = (self.page + step) % oled_preview.pages(n)
        self.page_at = time.monotonic()
        self._render()

    # ---------------- pratinjau & nilai langsung ----------------
    def _metrics(self):
        return select(self.worker.values or {}, [i for i in self.order if i in self.selected])

    def _render(self):
        metrics = self._metrics()
        p = oled_preview.pages(len(metrics))
        self.page %= p
        img = oled_preview.to_image(oled_preview.render(metrics, self.page), SCALE)
        self._photo = ImageTk.PhotoImage(img)
        self.preview.config(image=self._photo)
        self.page_lbl.config(text="Halaman %d/%d" % (self.page + 1, p) if metrics else "—")

    def _tick(self):
        if not self.win.winfo_exists():
            return
        values = self.worker.values or {}
        if tuple(values.get(i) is not None for i in IDS) != getattr(self, "_avail_key", None):
            self._rebuild_list()                          # sensor baru tersedia / hilang (mis. LibreHardwareMonitor)
        for mid, lbl in self.value_lbls.items():
            m = values.get(mid)
            lbl.config(text=_pretty(m) if m else "—")
        if time.monotonic() - self.page_at >= PAGE_MS / 1000:
            n = len(self._metrics())
            self.page = (self.page + 1) % oled_preview.pages(n)
            self.page_at = time.monotonic()
        self._render()
        st = self.worker.status + ("  ·  dijeda" if self.worker.paused else "")
        self.status.config(text="● " + st)
        if self.msg_until and time.monotonic() > self.msg_until:
            self.msg.config(text="")
            self.msg_until = 0.0
        self.win.after(1000, self._tick)
