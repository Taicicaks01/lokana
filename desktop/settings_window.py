"""Jendela pengaturan Lokana Desktop: pratinjau OLED 1:1 + pilih, urutkan, beri label, format, dan gabung metrik.

tkinter bawaan Python (tanpa dependensi GUI tambahan). Semua perubahan langsung berlaku dan disimpan ke
config Desktop (bukan firmware). Pratinjau dirender oleh oled_preview.py dari susunan yang sama dengan yang dikirim
ke Lokana (layout.build), jadi selalu sama dengan layar Lokana.
"""
import time
import tkinter as tk
from tkinter import ttk

from PIL import ImageTk

import layout
import oled_preview
from sensors import IDS, MAX_METRICS, NAMES, REASONS, TEMPLATES

PAGE_MS = 5000          # sama dengan modul Monitor: halaman berganti sendiri tiap 5 dtk
SCALE = 4
FORMATS = [("Otomatis", "auto"), ("0 desimal", 0), ("1 desimal", 1), ("2 desimal", 2)]
SEPS = [("Koma (1,25)", ","), ("Titik (1.25)", ".")]


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
        for key, default in (("labels", {}), ("decimals", {}), ("pairs", []), ("decimal_sep", ",")):
            cfg.setdefault(key, default)
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
        self.sep = ttk.Combobox(top, state="readonly", width=12, values=[n for n, _ in SEPS])
        seps = [v for _, v in SEPS]
        cur = self.cfg.get("decimal_sep", ",")
        self.sep.current(seps.index(cur) if cur in seps else 0)
        self.sep.bind("<<ComboboxSelected>>", lambda _e: self._sep_changed())
        self.sep.pack(side="right", padx=(4, 18))
        ttk.Label(top, text="Pemisah desimal").pack(side="right")

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
        self.note = ttk.Label(left, text="", wraplength=520, justify="center")
        self.note.pack(pady=(6, 0))

        right = ttk.Frame(self.win)
        right.grid(row=1, column=1, sticky="n", **pad)
        ttk.Label(right, text="Metrik yang tampil (maks %d, 4 baris per halaman)" % MAX_METRICS,
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

    def _cfg_preview(self):
        c = dict(self.cfg)
        c["metrics"] = [i for i in self.order if i in self.selected]
        return c

    def _layout(self):
        return layout.build(self.worker.values or {}, self._cfg_preview())

    def _rebuild_list(self):
        for w in self.list.winfo_children():
            w.destroy()
        values = self.worker.values or {}
        ids, _m, _t, rows = self._layout()
        info = {}                                     # id -> (nomor baris, "a" kiri / "b" digabung ke baris atas)
        for r, (a, b) in enumerate(rows):
            info[ids[a]] = (r, "a")
            if b is not None:
                info[ids[b]] = (r, "b")
        self.value_lbls = {}
        header_unsel = False
        row = 0
        for mid in self.order:
            on = mid in self.selected
            avail = values.get(mid) is not None
            r, role = info.get(mid, (None, None))
            if role == "a" and r % 4 == 0:
                ttk.Label(self.list, text="── Halaman %d " % (r // 4 + 1) + "─" * 40,
                          foreground="#C4386F").grid(row=row, column=0, columnspan=8, sticky="w", pady=(6, 0))
                row += 1
            if not on and not header_unsel:
                header_unsel = True
                ttk.Label(self.list, text="── Tidak ditampilkan " + "─" * 34,
                          foreground="#6b6170").grid(row=row, column=0, columnspan=8, sticky="w", pady=(6, 0))
                row += 1
            var = tk.BooleanVar(value=on)
            ttk.Checkbutton(self.list, variable=var, command=lambda m=mid, v=var: self._toggle(m, v)).grid(
                row=row, column=0, sticky="w")
            src = getattr(getattr(self.worker, "sensors", None), "cpu_temp_source", None) if mid == "cpu_temp" else None
            name = ("↳ " if role == "b" else "") + NAMES[mid] + ("  · " + src if (avail and src) else "")
            if not avail:
                name += "  (" + REASONS.get(mid, "tidak tersedia") + ")"
            editable = on and avail
            ttk.Label(self.list, text=name, width=26 if editable else 52,
                      foreground="#1B1720" if avail else "#9a8f9e").grid(
                row=row, column=1, columnspan=1 if editable else 4, sticky="w")
            if editable:
                # label sendiri (maks 10), format angka, gabung dengan metrik di bawahnya
                lv = tk.StringVar(value=self.cfg["labels"].get(mid, ""))
                ttk.Entry(self.list, textvariable=lv, width=11).grid(row=row, column=2, padx=(4, 0))
                lv.trace_add("write", lambda *_a, m=mid, v=lv: self._label_changed(m, v))
                fmt = ttk.Combobox(self.list, state="readonly", width=9, values=[n for n, _ in FORMATS])
                vals = [v for _, v in FORMATS]
                cur = self.cfg["decimals"].get(mid, "auto")
                fmt.current(vals.index(cur) if cur in vals else 0)
                fmt.bind("<<ComboboxSelected>>", lambda _e, m=mid, w=fmt: self._format_changed(m, w))
                fmt.grid(row=row, column=3, padx=4)
                can_pair = role == "a" and ids.index(mid) + 1 < len(ids)
                pv = tk.BooleanVar(value=can_pair and mid in self.cfg["pairs"])
                cb = ttk.Checkbutton(self.list, text="⤵ gabung", variable=pv,
                                     command=lambda m=mid, v=pv: self._pair_changed(m, v))
                cb.grid(row=row, column=4, sticky="w")
                if not can_pair:
                    cb.state(["disabled"])
            lbl = ttk.Label(self.list, text="", width=10, anchor="e")
            lbl.grid(row=row, column=5, sticky="e")
            self.value_lbls[mid] = lbl
            if on:
                ttk.Button(self.list, text="↑", width=3, command=lambda m=mid: self._move(m, -1)).grid(
                    row=row, column=6, padx=(6, 0))
                ttk.Button(self.list, text="↓", width=3, command=lambda m=mid: self._move(m, 1)).grid(
                    row=row, column=7)
            row += 1
        ttk.Label(self.list, text="Label: kosong = bawaan, maks 10 huruf (boleh °).  "
                  "⤵ gabung = tampil sebaris dengan metrik di bawahnya.",
                  foreground="#6b6170").grid(row=row, column=0, columnspan=8, sticky="w", pady=(8, 0))
        self._avail_key = tuple(values.get(i) is not None for i in IDS)

    # ---------------- aksi ----------------
    def _commit(self, rebuild=True):
        self.cfg["metrics"] = [i for i in self.order if i in self.selected]
        self.save()
        self.worker.kick.set()                        # kirim ke Lokana sekarang, tidak menunggu interval
        if rebuild:
            self._rebuild_list()
        self._render()

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
            self.order.remove(mid)                    # pindah ke akhir kelompok terpilih
            self.order.insert(len([i for i in self.order if i in self.selected]), mid)
        else:
            self.selected.discard(mid)
            self.order.remove(mid)
            self.order.append(mid)
        self._commit()

    def _move(self, mid, step):
        sel = [i for i in self.order if i in self.selected]
        i = sel.index(mid)
        j = i + step
        if 0 <= j < len(sel):
            sel[i], sel[j] = sel[j], sel[i]
            self.order = sel + [m for m in self.order if m not in self.selected]
            self._commit()

    def _label_changed(self, mid, var):
        text = layout.clean_label(var.get())
        if text != var.get():
            var.set(text)                             # Tcl tidak memanggil trace lagi dari dalam trace: lanjut simpan
        if text:
            self.cfg["labels"][mid] = text
        else:
            self.cfg["labels"].pop(mid, None)
        self._commit(rebuild=False)                   # daftar tidak dibangun ulang: kursor tetap di kotak label

    def _format_changed(self, mid, widget):
        val = FORMATS[widget.current()][1]
        if val == "auto":
            self.cfg["decimals"].pop(mid, None)
        else:
            self.cfg["decimals"][mid] = val
        self._commit(rebuild=False)

    def _pair_changed(self, mid, var):
        pairs = [p for p in self.cfg["pairs"] if p != mid]
        if var.get():
            pairs.append(mid)
        self.cfg["pairs"] = pairs
        self._commit()

    def _sep_changed(self):
        self.cfg["decimal_sep"] = SEPS[self.sep.current()][1]
        self._commit(rebuild=False)

    def _template(self, name):
        ids = TEMPLATES[name][:MAX_METRICS]
        self.selected = set(ids)
        self.order = list(ids) + [i for i in IDS if i not in ids]
        self.page = 0
        self.page_at = time.monotonic()
        self._commit()
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

    def _pages(self):
        _ids, metrics, _t, rows = self._layout()
        return oled_preview.pages(len(metrics) if self.worker.legacy else len(rows))

    def _flip(self, step):
        self.page = (self.page + step) % self._pages()
        self.page_at = time.monotonic()
        self._render()

    # ---------------- pratinjau & nilai langsung ----------------
    def _render(self):
        _ids, metrics, texts, rows = self._layout()
        legacy = bool(self.worker.legacy)
        p = oled_preview.pages(len(metrics) if legacy else len(rows))
        self.page %= p
        canvas = oled_preview.render(metrics, self.page, (0, 0), texts, rows, legacy)
        self._photo = ImageTk.PhotoImage(oled_preview.to_image(canvas, SCALE))
        self.preview.config(image=self._photo)
        self.page_lbl.config(text="Halaman %d/%d" % (self.page + 1, p) if metrics else "—")
        if legacy:
            self.note.config(foreground="#B4630F",
                             text="Lokana ini masih Lokana OS 0.7: label sendiri, format angka, dan ⤵ gabung baru "
                                  "tampil setelah diperbarui ke 0.8. Pratinjau menunjukkan layar Lokana saat ini.")
        else:
            self.note.config(foreground="#6b6170", text="Pratinjau 1:1 layar Monitor Lokana (128×64, diperbesar 4×)")

    def _tick(self):
        if not self.win.winfo_exists():
            return
        values = self.worker.values or {}
        if tuple(values.get(i) is not None for i in IDS) != getattr(self, "_avail_key", None):
            self._rebuild_list()                          # sensor baru tersedia / hilang (mis. LibreHardwareMonitor)
        sep = self.cfg.get("decimal_sep", ",")
        for mid, lbl in self.value_lbls.items():
            m = values.get(mid)
            lbl.config(text=layout.value_text(m, self.cfg["decimals"].get(mid, "auto"), sep) if m else "—")
        if time.monotonic() - self.page_at >= PAGE_MS / 1000:
            self.page = (self.page + 1) % self._pages()
            self.page_at = time.monotonic()
        self._render()
        st = self.worker.status + ("  ·  dijeda" if self.worker.paused else "")
        self.status.config(text="● " + st)
        if self.msg_until and time.monotonic() > self.msg_until:
            self.msg.config(text="")
            self.msg_until = 0.0
        self.win.after(1000, self._tick)
