"""Pratinjau layar Monitor Lokana (128x64) di PC, piksel demi piksel sama dengan firmware.

Port dari firmware/src/modules/monitor_module.cpp (render) + display::textWidth/centerText + Adafruit GFX
drawChar (font classic 5x7). **Kalau tata letak monitor_module.cpp berubah, ubah juga file ini**, lalu cek:

    python oled_preview.py --compare COM10      # bandingkan per piksel dengan layar Lokana asli

Geser piksel anti burn-in (1 px tiap 2 menit) tidak ditiru: PC tidak tahu kapan Lokana menggeser.
"""
import sys

from oled_font import GLCD

W, H = 128, 64
ROW_H = 16
ROWS = H // ROW_H            # 4 baris per halaman (128x64)


def v10(value):
    """Nilai x10 persis seperti yang dikirim di PC_STATS (lokana_link.p_pcstats)."""
    return int(round(value * 10))


def to_ascii(s, cap):
    """Sama dengan toAscii() firmware: non-ASCII -> '?', kontrol -> spasi, dipotong ke cap-1 karakter."""
    out = []
    for ch in s:
        c = ord(ch)
        if c >= 0x80:
            out.append("?")
        elif c < 0x20 or c == 0x7F:
            out.append(" ")
        else:
            out.append(ch)
        if len(out) >= cap - 1:
            break
    return "".join(out)


def _cdiv(a, b):
    """Pembagian bilangan bulat ala C (dibulatkan ke nol)."""
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b > 0) else -q


def format_value(kind, val10, unit):
    """formatValue() firmware: persen & suhu bulat; angka lain 1 desimal kalau < 100."""
    if kind in (1, 2) or val10 >= 1000 or val10 <= -1000:
        return "%d%s" % (_cdiv(val10 + 5 if val10 >= 0 else val10 - 5, 10), unit)
    return "%s%d.%d%s" % ("-" if val10 < 0 else "", abs(val10) // 10, abs(val10) % 10, unit)


class Canvas:
    """Bitmap 1-bit 128x64 dengan primitif Adafruit GFX yang dipakai modul Monitor."""

    def __init__(self):
        self.px = bytearray(W * H)

    def pixel(self, x, y):
        if 0 <= x < W and 0 <= y < H:
            self.px[y * W + x] = 1

    def fill_rect(self, x, y, w, h):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.pixel(xx, yy)

    def hline(self, x, y, w):
        self.fill_rect(x, y, w, 1)

    def text(self, x, y, s):
        """print() ukuran 1, font classic: 6 px per karakter, tanpa latar (transparan)."""
        for ch in s:
            c = ord(ch)
            if c == 10:
                continue
            for i in range(5):
                line = GLCD[c * 5 + i]
                for j in range(8):
                    if line & 1:
                        self.pixel(x + i, y + j)
                    line >>= 1
            x += 6


def text_width(s):
    return len(s) * 6                # display::textWidth (ukuran 1)


def pages(n):
    return (n + ROWS - 1) // ROWS if n else 1


def render(metrics, page=0, shift=(0, 0)):
    """metrics: [(kind, label, value, unit)] seperti PC_STATS. Hasil: Canvas 128x64."""
    g = Canvas()
    n = min(len(metrics), 12)
    if not n:
        msg = "Menunggu data PC"
        g.text(max(0, (W - text_width(msg)) // 2), H // 2 - 4, msg)
        return g
    p = pages(n)
    page = page % p
    ox, oy = shift
    bar_w = W - 3
    for r in range(ROWS):
        i = page * ROWS + r
        if i >= n:
            break
        kind, label, value, unit = metrics[i]
        val10 = v10(value)
        label, unit = to_ascii(label, 7), to_ascii(unit, 5)
        y = r * ROW_H + oy
        g.text(ox, y + 1, label)
        v = format_value(kind, val10, unit)
        g.text(ox + W - 2 - text_width(v), y + 1, v)
        if kind in (1, 2):
            pct = max(0, min(100, _cdiv(val10, 10)))
            bw = bar_w - 4 * p - 2 if (r == ROWS - 1 and p > 1) else bar_w
            g.hline(ox, y + 12, bw)
            g.fill_rect(ox, y + 10, pct * bw // 100, 3)
    if p > 1:
        for k in range(p):
            x, yy = ox + W - 2 - (p - 1 - k) * 4, H - 2 + oy - 1
            if k == page:
                g.fill_rect(x - 1, yy - 1, 2, 2)
            else:
                g.pixel(x, yy)
    return g


def to_image(canvas, scale=4, on=(0x9E, 0xE7, 0xFF), off=(0, 0, 0)):
    """Canvas -> PIL Image (warna OLED Lokana), diperbesar `scale` kali tanpa penghalusan."""
    from PIL import Image
    img = Image.new("RGB", (W, H), off)
    pix = img.load()
    for y in range(H):
        row = y * W
        for x in range(W):
            if canvas.px[row + x]:
                pix[x, y] = on
    return img.resize((W * scale, H * scale), Image.NEAREST) if scale != 1 else img


# ---------------- Pemeriksaan 1:1 terhadap Lokana asli ----------------
def _compare(port):
    import os
    import time
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "protocol", "tools"))
    import lokana_link as L

    sample = [(1, "CPU", 23.4, "%"), (1, "RAM", 61.0, "%"), (2, "CPU", 54.6, "C"), (2, "GPU", 47.0, "C"),
              (1, "GPU", 3.0, "%"), (0, "Unduh", 512.3, "KB/s"), (0, "Unggah", 0.8, "MB/s"), (0, "Disk", 12.25, "MB/s"),
              (1, "Batre+", 80.0, "%"), (0, "Negatf", -7.25, "x"), (7, "Label-panjang", 1234.5, "satuan")]

    def device():
        d = L._capture(lk)
        return bytearray(1 if d[y * 16 + x // 8] >> (7 - x % 8) & 1 else 0 for y in range(H) for x in range(W))

    def check(name, metrics, page):
        dev = device()
        best = None
        for s in ((0, 0), (1, 0), (1, 1), (0, 1)):
            diff = sum(1 for a, b in zip(render(metrics, page, s).px, dev) if a != b)
            if best is None or diff < best[0]:
                best = (diff, s)
        ok = best[0] == 0
        print("%-6s %s: %d piksel beda (geser %s)" % ("LULUS" if ok else "GAGAL", name, best[0], best[1]))
        return ok

    lk = L.Link(port, verbose=False)
    lk.request(L.T["HELLO"], L.p_hello("oled_preview --compare"))
    results = []
    lk.request(L.T["PC_STATS"], L.p_pcstats(sample))
    time.sleep(1.2)
    results.append(check("halaman 1 (persen, suhu)", sample, 0))
    lk.request(L.T["SCREEN"], bytes([L.SC["INPUT"], 1]))        # tap = halaman berikutnya
    time.sleep(0.6)
    lk.request(L.T["PC_STATS"], L.p_pcstats(sample))
    results.append(check("halaman 2 (angka, KB/s, MB/s)", sample, 1))
    lk.request(L.T["SCREEN"], bytes([L.SC["INPUT"], 1]))
    time.sleep(0.6)
    lk.request(L.T["PC_STATS"], L.p_pcstats(sample))
    results.append(check("halaman 3 (negatif, label panjang, kind lain)", sample, 2))
    lk.request(L.T["PC_STATS"], bytes([0]))
    time.sleep(0.6)
    results.append(check("tanpa metrik", [], 0))
    lk.close()
    print("%d/%d sama persis" % (sum(results), len(results)))
    return 0 if all(results) else 1


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "--compare":
        sys.exit(_compare(sys.argv[2]))
    print("pakai: python oled_preview.py --compare COMx")
