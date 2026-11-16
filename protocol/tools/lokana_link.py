#!/usr/bin/env python3
"""
lokana_link.py — penguji Lokana Link v1 lewat USB serial.

Spesifikasi: protocol/LOKANA_LINK.md
Butuh: pip install pyserial

Contoh:
  python lokana_link.py selftest                 # cek CRC & contoh byte spesifikasi (tanpa device)
  python lokana_link.py hello                    # HELLO -> DEVICE_INFO
  python lokana_link.py time                     # sinkron jam dari PC (zona waktu lokal)
  python lokana_link.py text "Halo Wayan"        # tampilkan teks
  python lokana_link.py text "Promo!" --style scroll --duration 10
  python lokana_link.py text "Wayan|KRTI 2026" --slot 1   # simpan ke slot 1 ('|' = baris baru)
  python lokana_link.py expr senang --hold 3000
  python lokana_link.py goto jam
  python lokana_link.py find --duration 5        # cari kunci;  find --stop  untuk berhenti
  python lokana_link.py settings                 # baca pengaturan
  python lokana_link.py settings --brightness 2 --timeout 60 --name "Lokana Wayan"
  python lokana_link.py dice d20                 # lempar dadu, tunggu hasilnya
  python lokana_link.py bitmap --demo senyum     # gambar bawaan: senyum, hati, catur
  python lokana_link.py bitmap --image logo.png --slot 1   # butuh Pillow: pip install pillow
  python lokana_link.py listen                   # dengarkan hasil dadu, tombol, cari HP
  python lokana_link.py notif WhatsApp "Ibu" "Sudah makan?"   # notifikasi (--important, --silent)
  python lokana_link.py notif --delete 1         # hapus notifikasi id 1
  python lokana_link.py call "Ibu"               # panggilan masuk;  call --stop  untuk selesai
  python lokana_link.py anim --demo bola --slot 2  # animasi bawaan: bola, denyut, kedip
  python lokana_link.py anim --gif kucing.gif     # GIF -> animasi (butuh Pillow)
  python lokana_link.py gallery                  # isi slot gambar 1-8 (gambar ASCII)
  python lokana_link.py screen                   # layar Lokana langsung di terminal (Ctrl+C keluar)
  python lokana_link.py screen --shot layar.png  # screenshot (butuh Pillow)
  python lokana_link.py press double             # gestur jarak jauh: tap double triple tahan
  python lokana_link.py test                     # uji otomatis semua pesan v0.3 - v0.5
  python lokana_link.py monitor                  # tampilkan log & frame dari device

Port dipilih otomatis (USB VID 303A = ESP32-C3). Pakai --port COM9 kalau ada beberapa.
"""
import argparse
import struct
import sys
import time

try:
    import serial
    import serial.tools.list_ports
except ImportError:  # selftest tetap bisa jalan tanpa pyserial
    serial = None

# ---------------- Konstanta protokol ----------------
T = dict(HELLO=0x00, TIME_SYNC=0x01, DEVICE_INFO=0x02, SETTINGS=0x03, OTA=0x04, ACK=0x05, UNPAIR=0x06,
         NOTIF=0x10, NAV=0x11, PC_STATS=0x12, MEETING=0x13, PHONE_STATS=0x14, CALL=0x15,
         FIND_KEYS=0x20, FIND_PHONE=0x21, EXPRESSION=0x22, DICE=0x23, GOTO=0x24, BUTTON=0x25,
         CUSTOM_TEXT=0x30, BITMAP=0x31, ANIM=0x32, SCREEN=0x33, TEXT_SLOT=0x34, WIFI_PROV=0x40, WIFI_STATUS=0x41)
TYPE_NAME = {v: k for k, v in T.items()}
STATUS = ["OK", "UNKNOWN_TYPE", "BAD_PAYLOAD", "BUSY", "NOT_SUPPORTED", "NOT_ALLOWED", "ERROR"]
EXPRESSIONS = ["netral", "senang", "sedih", "marah", "ngantuk", "kaget", "cinta",
               "pusing", "curiga", "bosan", "semangat", "gugup", "kedip"]
CAPS = ["NOTIF", "NAV", "PC_STATS", "PHONE_STATS", "CUSTOM_TEXT", "BITMAP", "OTA", "WIFI",
        "HID", "BUZZER", "DICE", "FIND_PHONE", "ANIM", "SCREEN", "TEXT_SLOT"]
STYLES = {"diam": 0, "static": 0, "scroll": 1, "jalan": 1, "blink": 2, "kedip": 2}
DICE = ["1d6", "2d6", "d4", "d8", "d10", "d12", "d20", "koin"]
GESTURES = {1: "tap", 2: "double", 3: "triple", 4: "tahan"}
# Key SETTINGS: nama -> (key, format struct; None = string)
SETTING_KEYS = {"brightness": (0x01, "<B"), "sound": (0x02, "<B"), "screen_timeout": (0x03, "<H"),
                "flip": (0x04, "<B"), "device_name": (0x05, None), "button_events": (0x06, "<B"),
                "notif_popup": (0x07, "<B"), "boot_guide": (0x08, "<B")}
FONTS = {"piksel": 0, "sans": 1, "sans-tebal": 2, "serif": 3, "mono-tebal": 4}
SETTING_NAME = {k: n for n, (k, _) in SETTING_KEYS.items()}
CLIENT_SCRIPT = 4
ACK_TIMEOUT = 2.0
RETRIES = 3


def crc16(data: bytes, crc: int = 0xFFFF) -> int:
    """CRC-16/CCITT-FALSE: poly 0x1021, init 0xFFFF, tanpa refleksi, tanpa XOR akhir."""
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if crc & 0x8000 else crc << 1
            crc &= 0xFFFF
    return crc


def frame(type_: int, seq: int, payload: bytes = b"") -> bytes:
    return struct.pack("<BBH", type_, seq, len(payload)) + payload


def envelope(fr: bytes) -> bytes:
    return b"\xA5\x5A" + fr + struct.pack("<H", crc16(fr))


def s(text: str) -> bytes:
    """str Lokana Link: u8 panjang + UTF-8 (maks 255 byte)."""
    b = text.encode("utf-8")[:255]
    return bytes([len(b)]) + b


# ---------------- Payload ----------------
def p_hello(name="lokana_link.py"):
    return bytes([1, CLIENT_SCRIPT]) + s(name)


def p_time(epoch=None, tz_min=None):
    if epoch is None:
        epoch = int(time.time())
    if tz_min is None:
        tz_min = time.localtime().tm_gmtoff // 60
    return struct.pack("<Ih", epoch, tz_min)


def p_text(text, style=0, size=0, duration=0, slot=0, font=None):
    p = struct.pack("<BBHB", style, size, duration, slot) + s(text.replace("|", "\n"))
    return p if font is None else p + bytes([font])          # font: field akhir opsional (0.5.2)


def p_expr(expr, hold=0):
    return struct.pack("<BH", expr, hold)


def p_find(on=True, duration=30):
    return bytes([1 if on else 0, duration])


def p_settings_get():
    return bytes([0])


def p_settings_set(**items):
    """SETTINGS SET: item TLV (key u8, len u8, value)."""
    out = bytearray([1])
    for name, v in items.items():
        key, fmt = SETTING_KEYS[name]
        val = v.encode("utf-8")[:24] if fmt is None else struct.pack(fmt, v)
        out += bytes([key, len(val)]) + val
    return bytes(out)


def parse_settings(p: bytes) -> dict:
    d, i = {"op": p[0]}, 1
    while i + 2 <= len(p):
        key, n = p[i], p[i + 1]
        v = p[i + 2:i + 2 + n]
        i += 2 + n
        name = SETTING_NAME.get(key, f"0x{key:02X}")
        if key == 0x05:
            d[name] = v.decode("utf-8", "replace")
        elif n == 2:
            d[name] = struct.unpack("<H", v)[0]
        elif n == 1:
            d[name] = v[0]
        else:
            d[name] = v.hex()
    return d


NOTIF_CATEGORIES = {"umum": 0, "pesan": 1, "email": 2, "sosmed": 3, "kalender": 4, "tak_terjawab": 5, "sistem": 6}


def p_notif(id_, app="", title="", body="", category=1, silent=False, important=False):
    flags = (1 if silent else 0) | (2 if important else 0)
    return struct.pack("<BIBB", 0, id_, category, flags) + s(app) + s(title) + s(body)


def p_notif_delete(id_):
    return struct.pack("<BI", 1, id_)


def p_call(ringing=True, caller=""):
    return bytes([0 if ringing else 1]) + s(caller)


SC = dict(START=0, STOP=1, FRAME=2, INPUT=3, CAPTURE=4)
GESTURE_ID = {"tap": 1, "double": 2, "triple": 3, "tahan": 4, "long": 4}

AO = dict(BEGIN=0, FRAME=1, END=2, ABORT=3, READ=4, LIST=5, LIST_REPORT=6, DELETE=7, SHOW=8)


def p_anim_begin(slot, frames, w, h, frame_ms=100, loops=0, duration=0, x=None, y=None):
    x = (128 - w) // 2 if x is None else x
    y = (64 - h) // 2 if y is None else y
    return struct.pack("<BBBHBHhhBB", AO["BEGIN"], slot, frames, frame_ms, loops, duration, x, y, w, h)


def p_anim_frame(i, data):
    return bytes([AO["FRAME"], i]) + bytes(data)


def demo_anim(name, w=64, h=64, n=8):
    """Animasi uji tanpa Pillow. Hasil: (w, h, [data bingkai])."""
    import math
    frames = []
    for f in range(n):
        px = [[0] * w for _ in range(h)]
        for y in range(h):
            for x in range(w):
                if name == "denyut":                     # lingkaran membesar-mengecil
                    r = (0.55 + 0.35 * math.sin(2 * math.pi * f / n)) * min(w, h) / 2
                    on = math.hypot(x - w / 2, y - h / 2) <= r
                elif name == "kedip":                    # kotak berkedip setengah waktu
                    on = f < n // 2 and 8 <= x < w - 8 and 8 <= y < h - 8
                else:                                    # bola memantul
                    cy = (h - 11) - abs(math.sin(math.pi * f / n)) * (h - 22)   # lantai -> puncak -> lantai
                    on = math.hypot(x - w / 2, y - cy) <= 9
                px[y][x] = 1 if on else 0
        frames.append(pack_bits(px))
    return w, h, frames


def gif_anim(path, max_w=128, max_h=64, max_frames=16):
    try:
        from PIL import Image, ImageSequence
    except ImportError:
        sys.exit("Pillow belum terpasang: pip install pillow")
    im = Image.open(path)
    all_frames = [f.copy() for f in ImageSequence.Iterator(im)]
    step = max(1, -(-len(all_frames) // max_frames))     # ambil merata jika terlalu banyak
    picked = all_frames[::step][:max_frames]
    out, size = [], None
    for f in picked:
        g = f.convert("L")
        g.thumbnail((max_w, max_h))
        size = size or g.size
        g = g.resize(size).convert("1")
        w, h = size
        out.append(pack_bits([[1 if g.getpixel((x, y)) else 0 for x in range(w)] for y in range(h)]))
    ms = im.info.get("duration", 100) * step
    return size[0], size[1], out, max(40, ms)


def p_dice(dice=255):
    return bytes([0, dice])


def parse_dice(p: bytes) -> dict:
    return dict(op=p[0], dice=p[1], values=list(p[3:3 + p[2]]))


def p_bitmap(op, slot, duration, x, y, w, h, data):
    return struct.pack("<BBHhhBB", op, slot, duration, x, y, w, h) + bytes(data)


def demo_bitmap(name, w=128, h=64):
    """Gambar uji tanpa Pillow: senyum, hati, catur. Hasil: (w, h, data)."""
    import math
    px = [[0] * w for _ in range(h)]
    cx, cy, k = w / 2, h / 2, min(w, h) / 64     # ukuran mengikuti w x h
    for y in range(h):
        for x in range(w):
            if name == "catur":
                on = ((x // 8) + (y // 8)) % 2 == 0
            elif name == "hati":
                u, v = (x - cx) / (24 * k), -(y - cy + 4 * k) / (22 * k)      # kurva hati (x^2+y^2-1)^3 - x^2 y^3 <= 0
                on = (u * u + v * v - 1) ** 3 - u * u * v ** 3 <= 0
            else:  # senyum
                r = math.hypot(x - cx, y - cy)
                eye = math.hypot(x - (cx - 11 * k), y - (cy - 8 * k)) < 4 * k or math.hypot(x - (cx + 11 * k), y - (cy - 8 * k)) < 4 * k
                mouth = 17 * k < r < 21 * k and y > cy + 4 * k
                on = (27 * k < r < 31 * k) or eye or mouth
            px[y][x] = 1 if on else 0
    return w, h, pack_bits(px)


def pack_bits(px):
    """Baris piksel 0/1 -> format bitmap Lokana Link (baris dibulatkan ke byte, MSB = kiri)."""
    out = bytearray()
    for row in px:
        for xb in range(0, len(row), 8):
            b = 0
            for k in range(8):
                if xb + k < len(row) and row[xb + k]:
                    b |= 0x80 >> k
            out.append(b)
    return bytes(out)


def image_bitmap(path, max_w=128, max_h=64, invert=False):
    try:
        from PIL import Image
    except ImportError:
        sys.exit("Pillow belum terpasang: pip install pillow  (atau pakai --demo)")
    im = Image.open(path).convert("L")
    im.thumbnail((max_w, max_h))
    im = im.convert("1")                        # dithering Floyd-Steinberg
    w, h = im.size
    px = [[(1 if im.getpixel((x, y)) else 0) ^ (1 if invert else 0) for x in range(w)] for y in range(h)]
    return w, h, pack_bits(px)


def ascii_art(w, h, data, scale_x=2):
    bw = (w + 7) // 8
    rows = []
    for y in range(0, h, 2):                              # 2 baris piksel per baris teks
        row = ""
        for x in range(0, w, scale_x):
            a = data[y * bw + x // 8] >> (7 - x % 8) & 1
            b = data[(y + 1) * bw + x // 8] >> (7 - x % 8) & 1 if y + 1 < h else 0
            row += " ▀▄█"[a | b << 1]
        rows.append(row)
    return "\n".join(rows)


def parse_device_info(p: bytes) -> dict:
    i = 0

    def u8():
        nonlocal i
        i += 1
        return p[i - 1]

    def st():
        nonlocal i
        n = u8()
        i += n
        return p[i - n:i].decode("utf-8", "replace")

    d = dict(proto_ver=u8(), device_type=u8(), fw_version=st())
    d["screen_w"], d["screen_h"] = struct.unpack_from("<HH", p, i); i += 4
    d["battery_pct"] = u8()
    d["flags"] = u8()
    d["caps"] = struct.unpack_from("<I", p, i)[0]; i += 4
    d["device_name"] = st()
    return d


def parse_text_item(p):
    """TEXT_SLOT ITEM (op 1): slot, style, size, font, text."""
    n = p[5]
    return {"slot": p[1], "style": p[2], "size": p[3], "font": p[4], "text": p[6:6 + n].decode("utf-8", "replace")}


def list_text_slots(lk, timeout=2.0):
    """TEXT_SLOT LIST -> {slot: item}. Kosong jika tidak ada balasan."""
    lk.frames.clear()
    if lk.request(T["TEXT_SLOT"], bytes([0])) != 0:
        return {}
    got, end = {}, time.time() + timeout
    while len(got) < 8 and time.time() < end:
        f = lk.wait_frame(lambda f: f[0] == T["TEXT_SLOT"], end - time.time())
        if f and len(f[2]) >= 6 and f[2][0] == 1:
            it = parse_text_item(f[2])
            got[it["slot"]] = it
    return got


def describe(type_, seq, payload) -> str:
    name = TYPE_NAME.get(type_, f"0x{type_:02X}")
    if type_ == T["ACK"] and len(payload) >= 2:
        st = STATUS[payload[1]] if payload[1] < len(STATUS) else payload[1]
        return f"ACK seq={seq} untuk {TYPE_NAME.get(payload[0], hex(payload[0]))}: {st}"
    if type_ == T["TEXT_SLOT"] and len(payload) >= 6 and payload[0] == 1:
        it = parse_text_item(payload)
        return f"TEXT_SLOT slot {it['slot']}: " + (repr(it["text"]) + f" gaya {it['style']} ukuran {it['size']} font {it['font']}"
                                                 if it["text"] else "kosong")
    if type_ == T["DEVICE_INFO"]:
        d = parse_device_info(payload)
        caps = [c for b, c in enumerate(CAPS) if d["caps"] >> b & 1]
        flags = [f for b, f in enumerate(["USB", "WiFi", "bonded"]) if d["flags"] >> b & 1]
        bat = "?" if d["battery_pct"] == 255 else f'{d["battery_pct"]}%'
        return (f'DEVICE_INFO: {d["device_name"]} fw {d["fw_version"]} proto {d["proto_ver"]} '
                f'layar {d["screen_w"]}x{d["screen_h"]} baterai {bat} flags {flags} caps {caps}')
    if type_ == T["SETTINGS"] and payload:
        d = parse_settings(payload)
        d.pop("op")
        return "SETTINGS REPORT: " + ", ".join(f"{k}={v!r}" for k, v in d.items())
    if type_ == T["DICE"] and len(payload) >= 3:
        d = parse_dice(payload)
        nm = DICE[d["dice"]] if d["dice"] < len(DICE) else d["dice"]
        vals = ["angka" if v == 0 else "gambar" for v in d["values"]] if nm == "koin" else d["values"]
        return f"DICE hasil {nm}: {vals}"
    if type_ == T["BUTTON"] and payload:
        mod = payload[2:2 + payload[1]].decode("utf-8", "replace") if len(payload) > 1 else "?"
        return f"BUTTON {GESTURES.get(payload[0], payload[0])} di modul {mod}"
    if type_ == T["FIND_KEYS"] and payload:
        return "FIND_KEYS dari device: " + (f"bunyi {payload[1] if len(payload) > 1 else '?'} dtk" if payload[0] else "berhenti")
    if type_ == T["SCREEN"] and len(payload) >= 4 and payload[0] == SC["FRAME"]:
        return f"SCREEN FRAME {payload[2]}x{payload[3]} layar {'nyala' if payload[1] & 1 else 'mati'}"
    if type_ == T["ANIM"] and payload:
        op = payload[0]
        if op == AO["LIST_REPORT"]:
            slots = [f"{i + 1}:{payload[1 + 3 * i]}b {payload[2 + 3 * i]}x{payload[3 + 3 * i]}"
                     for i in range(8) if payload[1 + 3 * i]]
            return "ANIM LIST: " + (", ".join(slots) or "galeri kosong")
        if op == AO["BEGIN"]:
            return f"ANIM BEGIN slot {payload[1]} {payload[2]} bingkai {payload[12]}x{payload[13]}"
        if op == AO["FRAME"]:
            return f"ANIM FRAME {payload[1]} ({len(payload) - 2} B)"
        if op == AO["END"]:
            return "ANIM END"
    if type_ == T["FIND_PHONE"] and payload:
        return "FIND_PHONE " + ("bunyikan HP!" if payload[0] else "hentikan")
    return f"{name} seq={seq} payload={payload.hex(' ')}"


# ---------------- Koneksi USB ----------------
class Link:
    def __init__(self, port=None, verbose=True):
        if serial is None:
            sys.exit("pyserial belum terpasang: pip install pyserial")
        port = port or self.find_port()
        self.verbose = verbose
        self.ser = serial.Serial()
        self.ser.port, self.ser.baudrate, self.ser.timeout = port, 115200, 0.05
        # Buka tanpa DTR/RTS (bisa me-reset ESP32-C3), lalu nyalakan DTR supaya USB CDC mengirim
        self.ser.dtr = False
        self.ser.rts = False
        self.ser.open()
        time.sleep(1.0)
        self.ser.dtr = True
        time.sleep(0.3)
        self.ser.reset_input_buffer()
        self.seq = 0
        self.buf = bytearray()
        self.frames = []          # (type, seq, payload) yang sudah diterima
        self.text = bytearray()   # teks console yang sudah diterima
        if verbose:
            print(f"[usb] {port} terbuka")

    @staticmethod
    def find_port():
        ports = [p for p in serial.tools.list_ports.comports() if p.vid == 0x303A]
        if not ports:
            sys.exit("Board ESP32-C3 (VID 303A) tidak ditemukan. Pakai --port COMx")
        if len(ports) > 1:
            print("Beberapa board ditemukan, memakai", ports[0].device, "(pilih dengan --port)")
        return ports[0].device

    def close(self):
        self.ser.close()

    def next_seq(self):
        self.seq = self.seq % 255 + 1
        return self.seq

    def write_raw(self, data: bytes):
        self.ser.write(data)
        self.ser.flush()

    def poll(self, duration=0.1):
        """Baca port selama `duration` detik; pisahkan teks console dan frame."""
        end = time.time() + duration
        while time.time() < end:
            self.buf += self.ser.read(4096)
            self._parse()

    def _parse(self):
        while True:
            i = self.buf.find(b"\xA5\x5A")
            if i < 0:
                keep = 1 if self.buf.endswith(b"\xA5") else 0
                self._text(self.buf[:len(self.buf) - keep])
                del self.buf[:len(self.buf) - keep]
                return
            self._text(self.buf[:i])
            del self.buf[:i]
            if len(self.buf) < 6:
                return
            n = self.buf[4] | self.buf[5] << 8
            if len(self.buf) < 2 + 4 + n + 2:
                return
            fr = bytes(self.buf[2:6 + n])
            crc = self.buf[6 + n] | self.buf[7 + n] << 8
            del self.buf[:8 + n]
            if crc != crc16(fr):
                print("[usb] frame dari device: CRC salah, dibuang")
                continue
            item = (fr[0], fr[1], fr[4:])
            self.frames.append(item)
            if self.verbose:
                print("  <-", describe(*item))

    def _text(self, b):
        if not b:
            return
        self.text += b
        if self.verbose:
            for line in bytes(b).decode("utf-8", "replace").replace("\r", "").split("\n"):
                if line.strip():
                    print("  [log]", line)

    def wait_frame(self, pred, timeout):
        end = time.time() + timeout
        while time.time() < end:
            for f in self.frames:
                if pred(f):
                    self.frames.remove(f)
                    return f
            self.poll(0.05)
        return None

    def request(self, type_, payload=b"", ack=True, retries=RETRIES):
        """Kirim frame. Dengan ack=True tunggu ACK (2 dtk, kirim ulang maks 3x). Hasil: status atau None."""
        seq = self.next_seq() if ack else 0
        fr = frame(type_, seq, payload)
        for attempt in range(retries if ack else 1):
            if self.verbose:
                print(f"  -> {TYPE_NAME.get(type_, hex(type_))} seq={seq} len={len(payload)}"
                      + (f" (ulang {attempt})" if attempt else ""))
            self.write_raw(envelope(fr))
            if not ack:
                self.poll(0.2)
                return None
            f = self.wait_frame(lambda f: f[0] == T["ACK"] and f[1] == seq, ACK_TIMEOUT)
            if f:
                return f[2][1]
        return None


# ---------------- Perintah ----------------
def cmd_selftest(_args):
    ok = True

    def check(label, got, want):
        nonlocal ok
        good = got == want
        ok &= good
        print(f"  {'OK  ' if good else 'GAGAL'} {label}: {got}" + ("" if good else f" (harusnya {want})"))

    print("Uji tanpa device:")
    check("CRC '123456789'", hex(crc16(b"123456789")), "0x29b1")
    fr = frame(T["TIME_SYNC"], 0, p_time(1794798000, 480))
    check("frame TIME_SYNC contoh spek bag. 10", fr.hex(" "), "01 00 06 00 b0 71 fa 6a e0 01")
    check("envelope TIME_SYNC contoh spek bag. 10", envelope(fr).hex(" "), "a5 5a 01 00 06 00 b0 71 fa 6a e0 01 13 e9")
    check("ACK contoh spek bag. 10", frame(T["ACK"], 7, bytes([T["CUSTOM_TEXT"], 0])).hex(" "), "05 07 02 00 30 00")
    return 0 if ok else 1


def cmd_hello(a):
    lk = Link(a.port)
    st = lk.request(T["HELLO"], p_hello())
    lk.wait_frame(lambda f: f[0] == T["DEVICE_INFO"], 1.0)
    lk.close()
    return 0 if st == 0 else 1


def simple(type_key, payload_fn):
    def run(a):
        lk = Link(a.port)
        lk.request(T["HELLO"], p_hello())
        st = lk.request(T[type_key], payload_fn(a))
        lk.poll(0.3)
        lk.close()
        if st is None:
            print("Tidak ada ACK dari device.")
            return 1
        print("Status:", STATUS[st] if st < len(STATUS) else st)
        return 0 if st == 0 else 1
    return run


def expr_id(v):
    if v.isdigit():
        return int(v)
    v = v.lower()
    if v not in EXPRESSIONS:
        sys.exit("ekspresi: " + " ".join(EXPRESSIONS))
    return EXPRESSIONS.index(v)


def dice_id(v):
    v = v.lower()
    if v.isdigit():
        return int(v)
    if v not in DICE:
        sys.exit("dadu: " + " ".join(DICE))
    return DICE.index(v)


def onoff(v):
    return 1 if str(v).lower() in ("1", "on", "nyala", "ya") else 0


def cmd_settings(a):
    lk = Link(a.port)
    lk.request(T["HELLO"], p_hello())
    items = {}
    if a.brightness is not None: items["brightness"] = a.brightness
    if a.sound is not None: items["sound"] = onoff(a.sound)
    if a.timeout is not None: items["screen_timeout"] = a.timeout
    if a.flip is not None: items["flip"] = onoff(a.flip)
    if a.name is not None: items["device_name"] = a.name
    if a.notif_popup is not None: items["notif_popup"] = a.notif_popup
    if a.boot_guide is not None: items["boot_guide"] = onoff(a.boot_guide)
    st = lk.request(T["SETTINGS"], p_settings_set(**items) if items else p_settings_get())
    lk.wait_frame(lambda f: f[0] == T["SETTINGS"], 1.0)
    lk.close()
    return 0 if st == 0 else 1


def cmd_textslots(a):
    lk = Link(a.port, verbose=False)
    lk.request(T["HELLO"], p_hello())
    if a.show:
        st = lk.request(T["TEXT_SLOT"], struct.pack("<BBH", 2, a.show, a.duration))
        print(f"tampilkan slot {a.show}:", STATUS[st] if st is not None and st < len(STATUS) else st)
    else:
        items = list_text_slots(lk)
        for n in range(1, 9):
            it = items.get(n)
            print(f"  slot {n}: " + ("(tidak ada balasan)" if it is None else repr(it["text"]) if it["text"] else "kosong"))
    lk.close()
    return 0


def cmd_dice(a):
    lk = Link(a.port)
    lk.request(T["HELLO"], p_hello())
    st = lk.request(T["DICE"], p_dice(dice_id(a.dice) if a.dice else 255))
    if st == 0:
        lk.wait_frame(lambda f: f[0] == T["DICE"], 3.0)
    lk.close()
    return 0 if st == 0 else 1


def cmd_bitmap(a):
    if a.image:
        w, h, data = image_bitmap(a.image, invert=a.invert)
    else:
        w, h, data = demo_bitmap(a.demo)
    x = (128 - w) // 2 if a.x is None else a.x
    y = (64 - h) // 2 if a.y is None else a.y
    lk = Link(a.port)
    lk.request(T["HELLO"], p_hello())
    payload = p_bitmap(1 if a.slot else 0, a.slot, a.duration, x, y, w, h, data)
    print(f"  gambar {w}x{h} di ({x},{y}), {len(data)} byte")
    st = lk.request(T["BITMAP"], payload)
    lk.poll(0.3)
    lk.close()
    print("Status:", STATUS[st] if st is not None and st < len(STATUS) else st)
    return 0 if st == 0 else 1


def cmd_notif(a):
    lk = Link(a.port)
    lk.request(T["HELLO"], p_hello())
    if a.delete is not None:
        st = lk.request(T["NOTIF"], p_notif_delete(a.delete))
    else:
        st = lk.request(T["NOTIF"], p_notif(a.id, a.app, a.title, a.body, NOTIF_CATEGORIES[a.category],
                                            a.silent, a.important))
    lk.poll(0.3)
    lk.close()
    print("Status:", STATUS[st] if st is not None and st < len(STATUS) else st)
    return 0 if st == 0 else 1


def cmd_call(a):
    lk = Link(a.port)
    lk.request(T["HELLO"], p_hello())
    st = lk.request(T["CALL"], p_call(not a.stop, a.caller or ""))
    lk.poll(0.3)
    lk.close()
    print("Status:", STATUS[st] if st is not None and st < len(STATUS) else st)
    return 0 if st == 0 else 1


def send_anim(lk, slot, w, h, frames, frame_ms=100, loops=0, duration=0, x=None, y=None):
    """BEGIN -> FRAME... -> END. Hasil: status END (atau status gagal pertama)."""
    st = lk.request(T["ANIM"], p_anim_begin(slot, len(frames), w, h, frame_ms, loops, duration, x, y))
    if st != 0:
        return st
    for i, d in enumerate(frames):
        st = lk.request(T["ANIM"], p_anim_frame(i, d))
        if st != 0:
            return st
    return lk.request(T["ANIM"], bytes([AO["END"]]))


def read_slot(lk, slot, first_only=False, timeout=5.0):
    """ANIM READ -> (info BEGIN, [bingkai]) atau None."""
    lk.frames.clear()
    st = lk.request(T["ANIM"], bytes([AO["READ"], slot, 1 if first_only else 0]))
    if st != 0:
        return st, None, []
    begin, frames = None, []
    end = time.time() + timeout
    while time.time() < end:
        f = lk.wait_frame(lambda f: f[0] == T["ANIM"], 0.5)
        if not f:
            continue
        p_ = f[2]
        if p_[0] == AO["BEGIN"]:
            begin = struct.unpack("<BBBHBHhhBB", p_[:14])
        elif p_[0] == AO["FRAME"]:
            frames.append(p_[2:])
        elif p_[0] == AO["END"]:
            break
    return st, begin, frames


def cmd_anim(a):
    if a.gif:
        w, h, frames, ms = gif_anim(a.gif)
    else:
        w, h, frames = demo_anim(a.demo)
        ms = a.ms
    lk = Link(a.port)
    lk.request(T["HELLO"], p_hello())
    print(f"  animasi {len(frames)} bingkai {w}x{h}, {ms} ms/bingkai")
    st = send_anim(lk, a.slot, w, h, frames, ms, a.loops, a.duration)
    lk.poll(0.3)
    lk.close()
    print("Status:", STATUS[st] if st is not None and st < len(STATUS) else st)
    return 0 if st == 0 else 1


def cmd_gallery(a):
    sys.stdout.reconfigure(encoding="utf-8")       # karakter blok untuk gambar ASCII
    lk = Link(a.port, verbose=False)
    lk.request(T["HELLO"], p_hello())
    lk.request(T["ANIM"], bytes([AO["LIST"]]))
    f = lk.wait_frame(lambda f: f[0] == T["ANIM"] and f[2][0] == AO["LIST_REPORT"], 1.0)
    if not f:
        print("Tidak ada balasan LIST")
        return 1
    for i in range(8):
        n, w, h = f[2][1 + 3 * i: 4 + 3 * i]
        if not n:
            print(f"Slot {i + 1}: kosong")
            continue
        _, begin, frames = read_slot(lk, i + 1, first_only=True)
        print(f"Slot {i + 1}: {n} bingkai {w}x{h}")
        if frames:
            print(ascii_art(w, h, frames[0]))
    lk.close()
    return 0


def cmd_screen(a):
    sys.stdout.reconfigure(encoding="utf-8")
    lk = Link(a.port, verbose=False)
    lk.request(T["HELLO"], p_hello("lokana_link.py screen"))
    if a.shot:
        lk.frames.clear()
        lk.request(T["SCREEN"], bytes([SC["CAPTURE"]]))
        f = lk.wait_frame(lambda f: f[0] == T["SCREEN"] and f[2][0] == SC["FRAME"], 2.0)
        lk.close()
        if not f:
            print("Tidak ada FRAME")
            return 1
        _, flags, w, h = f[2][:4]
        try:
            from PIL import Image
        except ImportError:
            sys.exit("Pillow belum terpasang: pip install pillow")
        img = Image.new("RGB", (w, h))
        bw = (w + 7) // 8
        data = f[2][4:]
        on = (0x9E, 0xE7, 0xFF)
        for y in range(h):
            for x in range(w):
                img.putpixel((x, y), on if data[y * bw + x // 8] >> (7 - x % 8) & 1 else (0, 0, 0))
        img.resize((w * 4, h * 4), Image.NEAREST).save(a.shot)
        print(f"Screenshot {w}x{h} disimpan: {a.shot}")
        return 0
    lk.request(T["SCREEN"], bytes([SC["START"], a.fps]))
    last_start = time.time()
    print("\033[2J", end="")
    try:
        while True:
            if time.time() - last_start > 10:            # ulangi START supaya mirror tidak berhenti
                lk.request(T["SCREEN"], bytes([SC["START"], a.fps]), ack=False)
                last_start = time.time()
            f = lk.wait_frame(lambda f: f[0] == T["SCREEN"] and f[2][0] == SC["FRAME"], 0.5)
            if f:
                _, flags, w, h = f[2][:4]
                print("\033[H" + ascii_art(w, h, f[2][4:], 1) + f"\n layar {'nyala' if flags & 1 else 'mati'}   ")
    except KeyboardInterrupt:
        pass
    lk.request(T["SCREEN"], bytes([SC["STOP"]]))
    lk.close()
    return 0


def cmd_press(a):
    lk = Link(a.port)
    lk.request(T["HELLO"], p_hello())
    st = lk.request(T["SCREEN"], bytes([SC["INPUT"], GESTURE_ID[a.gesture]]))
    lk.poll(0.3)
    lk.close()
    return 0 if st == 0 else 1


def cmd_listen(a):
    lk = Link(a.port)
    lk.request(T["HELLO"], p_hello("lokana_link.py listen"))
    lk.request(T["SETTINGS"], p_settings_set(button_events=1))
    print("Mendengarkan (Ctrl+C keluar): sentuh Lokana, lempar dadu, atau menu -> Cari HP.")
    print("Jangan ketik perintah console di sini: itu menghentikan pesan dari device.")
    try:
        while True:
            lk.poll(0.2)
    except KeyboardInterrupt:
        pass
    lk.close()
    return 0


def cmd_monitor(a):
    lk = Link(a.port)
    print("Monitor (Ctrl+C untuk keluar). Ketik di monitor serial biasa untuk perintah console.")
    try:
        while True:
            lk.poll(0.2)
    except KeyboardInterrupt:
        pass
    lk.close()
    return 0


def test_v05b(lk, expect):
    """v0.5 (lanjutan): nama Bluetooth, UNPAIR, FIND_KEYS D->H, ANIM."""
    lk.request(T["HELLO"], p_hello("lokana_link.py test"))
    info = lk.wait_frame(lambda f: f[0] == T["DEVICE_INFO"], 1.0)
    caps = parse_device_info(info[2])["caps"] if info else 0
    expect("DEVICE_INFO caps ANIM", bool(caps >> CAPS.index("ANIM") & 1), True)

    # Nama Bluetooth UTF-8
    lk.frames.clear()
    lk.request(T["SETTINGS"], p_settings_get())
    rep_ = lk.wait_frame(lambda f: f[0] == T["SETTINGS"], 1.0)
    orig = parse_settings(rep_[2]).get("device_name") if rep_ else None
    expect("REPORT nama tidak kosong", bool(orig), True)
    lk.frames.clear()
    lk.request(T["SETTINGS"], p_settings_set(device_name="Lokana_लोचन-99"))
    rep_ = lk.wait_frame(lambda f: f[0] == T["SETTINGS"], 1.0)
    expect("nama Dewanagari tersimpan utuh", parse_settings(rep_[2]).get("device_name") if rep_ else None,
           "Lokana_लोचन-99", raw=True)
    lk.frames.clear()
    lk.request(T["SETTINGS"], p_settings_set(device_name="Lokana_" + "लोचन" * 4))
    rep_ = lk.wait_frame(lambda f: f[0] == T["SETTINGS"], 1.0)
    got = parse_settings(rep_[2]).get("device_name", "") if rep_ else ""
    expect("nama panjang dipotong <= 26 byte di batas huruf",
           len(got.encode()) <= 26 and "\ufffd" not in got and got.startswith("Lokana_"), True)
    if orig:
        lk.request(T["SETTINGS"], p_settings_set(device_name=orig))
    expect("UNPAIR lewat USB", lk.request(T["UNPAIR"]), 5)

    # FIND_KEYS: device melapor mulai & berhenti
    lk.frames.clear()
    lk.request(T["FIND_KEYS"], p_find(True, 3))
    f = lk.wait_frame(lambda f: f[0] == T["FIND_KEYS"], 1.0)
    expect("FIND_KEYS D->H: mulai", f[2][0] if f else None, 1, raw=True)
    lk.request(T["FIND_KEYS"], p_find(False))
    f = lk.wait_frame(lambda f: f[0] == T["FIND_KEYS"], 1.0)
    expect("FIND_KEYS D->H: berhenti", f[2][0] if f else None, 0, raw=True)

    # ANIM: kirim ke slot 8, daftar, baca, tampilkan, hapus
    w, h, frames = demo_anim("bola", 32, 32, 4)
    expect("ANIM 4 bingkai 32x32 ke slot 8", send_anim(lk, 8, w, h, frames, 150), 0)
    lk.frames.clear()
    lk.request(T["ANIM"], bytes([AO["LIST"]]))
    f = lk.wait_frame(lambda f: f[0] == T["ANIM"] and f[2][0] == AO["LIST_REPORT"], 1.0)
    expect("ANIM LIST: slot 8 = 4 bingkai 32x32", tuple(f[2][22:25]) if f else None, (4, 32, 32), raw=True)
    st, begin, got = read_slot(lk, 8, first_only=True)
    expect("ANIM READ slot 8 (bingkai pertama)", (st, len(got), got[0] if got else None), (0, 1, frames[0]), raw=True)
    st, begin, got = read_slot(lk, 8)
    expect("ANIM READ slot 8 (semua bingkai sama)", got == list(frames) and st == 0, True)
    expect("ANIM SHOW slot 8 2 dtk", lk.request(T["ANIM"], bytes([AO["SHOW"], 8, 2, 0])), 0)
    time.sleep(1.0)
    expect("BITMAP lama ke slot 7 (galeri sama)", lk.request(T["BITMAP"], p_bitmap(1, 7, 0, 0, 0, 8, 2, b"\xff\x81")), 0)
    lk.frames.clear()
    lk.request(T["ANIM"], bytes([AO["LIST"]]))
    f = lk.wait_frame(lambda f: f[0] == T["ANIM"] and f[2][0] == AO["LIST_REPORT"], 1.0)
    expect("ANIM LIST: slot 7 = BITMAP 1 bingkai", tuple(f[2][19:22]) if f else None, (1, 8, 2), raw=True)
    expect("ANIM DELETE slot 7", lk.request(T["ANIM"], bytes([AO["DELETE"], 7])), 0)
    expect("ANIM DELETE slot 8", lk.request(T["ANIM"], bytes([AO["DELETE"], 8])), 0)
    st, _, _ = read_slot(lk, 8, timeout=0.5)
    expect("ANIM READ slot kosong", st, 6)
    expect("ANIM SHOW slot kosong", lk.request(T["ANIM"], bytes([AO["SHOW"], 8, 0, 0])), 6)
    expect("ANIM BEGIN 17 bingkai layar penuh (> 16 KB)", lk.request(T["ANIM"], p_anim_begin(0, 17, 128, 64)), 2)
    lk.request(T["ANIM"], bytes([AO["ABORT"]]))
    expect("ANIM FRAME tanpa BEGIN", lk.request(T["ANIM"], p_anim_frame(0, bytes(128))), 2)
    lk.request(T["ANIM"], p_anim_begin(0, 2, 32, 32))
    lk.request(T["ANIM"], p_anim_frame(0, frames[0]))
    expect("ANIM END dengan bingkai kurang", lk.request(T["ANIM"], bytes([AO["END"]])), 6)
    lk.request(T["ANIM"], bytes([AO["ABORT"]]))
    expect("ANIM op 99 (belum ada)", lk.request(T["ANIM"], bytes([99])), 4)
    expect("ANIM tampil sekarang 2 dtk", send_anim(lk, 0, w, h, frames, 120, 0, 2), 0)
    time.sleep(2.3)


def test_v05c(lk, expect):
    """v0.5: SCREEN (mirror, screenshot, gestur jarak jauh)."""
    lk.request(T["HELLO"], p_hello("lokana_link.py test"))
    info = lk.wait_frame(lambda f: f[0] == T["DEVICE_INFO"], 1.0)
    caps = parse_device_info(info[2])["caps"] if info else 0
    expect("DEVICE_INFO caps SCREEN", bool(caps >> CAPS.index("SCREEN") & 1), True)
    lk.frames.clear()
    expect("SCREEN CAPTURE", lk.request(T["SCREEN"], bytes([SC["CAPTURE"]])), 0)
    f = lk.wait_frame(lambda f: f[0] == T["SCREEN"], 1.5)
    expect("SCREEN FRAME 128x64 (1024 B)", (f[2][2], f[2][3], len(f[2]) - 4) if f else None, (128, 64, 1024), raw=True)
    lk.frames.clear()
    expect("SCREEN START 10 fps", lk.request(T["SCREEN"], bytes([SC["START"], 10])), 0)
    expect("SCREEN INPUT double (pindah modul)", lk.request(T["SCREEN"], bytes([SC["INPUT"], 2])), 0)
    lk.poll(1.5)
    n = len([f for f in lk.frames if f[0] == T["SCREEN"]])
    expect(f"SCREEN mengirim bingkai saat layar berubah ({n})", n >= 2, True)
    expect("SCREEN STOP", lk.request(T["SCREEN"], bytes([SC["STOP"]])), 0)
    lk.poll(0.3)
    lk.frames.clear()
    lk.poll(2.5)
    expect("SCREEN berhenti setelah STOP", len([f for f in lk.frames if f[0] == T["SCREEN"]]), 0, raw=True)
    expect("SCREEN INPUT gestur 9", lk.request(T["SCREEN"], bytes([SC["INPUT"], 9])), 2)
    expect("SCREEN op 9 (belum ada)", lk.request(T["SCREEN"], bytes([9])), 4)
    lk.request(T["GOTO"], s("lokana"))


def _capture(lk):
    lk.frames.clear()
    lk.request(T["SCREEN"], bytes([SC["CAPTURE"]]))
    f = lk.wait_frame(lambda f: f[0] == T["SCREEN"] and f[2][0] == SC["FRAME"], 1.5)
    return f[2][4:] if f else b""


def test_v052(lk, expect):
    """v0.5.2: SETTINGS notif_popup, font CUSTOM_TEXT, modul Cari HP."""
    lk.request(T["HELLO"], p_hello("lokana_link.py test"))
    lk.frames.clear()
    lk.request(T["SETTINGS"], p_settings_get())
    rep_ = lk.wait_frame(lambda f: f[0] == T["SETTINGS"], 1.0)
    orig = parse_settings(rep_[2]).get("notif_popup") if rep_ else None
    expect("REPORT berisi notif_popup", orig is not None, True)

    def popup(v):
        lk.frames.clear()
        lk.request(T["SETTINGS"], p_settings_set(notif_popup=v))
        r = lk.wait_frame(lambda f: f[0] == T["SETTINGS"], 1.0)
        return parse_settings(r[2]).get("notif_popup") if r else None
    expect("notif_popup 10 dtk", popup(10), 10, raw=True)
    expect("notif_popup 1 dibulatkan ke 3", popup(1), 3, raw=True)
    expect("notif_popup 200 dibatasi 60", popup(200), 60, raw=True)
    expect("notif_popup 0 (tidak muncul)", popup(0), 0, raw=True)

    # Popup mati: notifikasi masuk tidak membuka layar Notif (bilah judul terbalik di baris atas)
    lk.request(T["GOTO"], s("lokana"))
    time.sleep(1.2)
    lk.request(T["NOTIF"], p_notif(0x52, "Uji", "Popup mati", "tidak boleh muncul", silent=True))
    time.sleep(0.4)
    d = _capture(lk)
    expect("notif_popup 0: layar tidak berpindah ke Notif", d[0:16] == b"\xff" * 16, False)
    popup(5)
    lk.request(T["NOTIF"], p_notif(0x53, "Uji", "Popup nyala", "harus muncul", silent=True))
    time.sleep(0.4)
    d = _capture(lk)
    expect("notif_popup 5: popup Notif muncul", d[0:16] == b"\xff" * 16, True)
    lk.request(T["SCREEN"], bytes([SC["INPUT"], 1]))      # tap = tutup popup
    for i in (0x52, 0x53):
        lk.request(T["NOTIF"], p_notif_delete(i))
    popup(orig if orig is not None else 6)

    # Font CUSTOM_TEXT
    shots = {}
    for f in (0, 1, 2, 3, 4):
        expect(f"CUSTOM_TEXT font {f}", lk.request(T["CUSTOM_TEXT"], p_text("Halo Lokana", font=f)), 0)
        time.sleep(0.3)
        shots[f] = _capture(lk)
    expect("tiap font tampil berbeda", len(set(shots.values())), 5, raw=True)
    expect("CUSTOM_TEXT font 9 (belum ada) = piksel", lk.request(T["CUSTOM_TEXT"], p_text("Halo Lokana", font=9)), 0)
    time.sleep(0.3)
    expect("font tidak dikenal tampil seperti font piksel", _capture(lk) == shots[0], True)
    expect("CUSTOM_TEXT tanpa field font (host lama)", lk.request(T["CUSTOM_TEXT"], p_text("Halo Lokana")), 0)
    time.sleep(0.3)
    expect("tanpa font = font piksel", _capture(lk) == shots[0], True)
    expect("CUSTOM_TEXT font Serif ukuran 3 berjalan",
           lk.request(T["CUSTOM_TEXT"], p_text("Teks berjalan panjang dengan font serif", style=1, size=3, font=3)), 0)
    lk.request(T["SCREEN"], bytes([SC["INPUT"], 1]))

    # Cari HP sekarang modul biasa: bisa dibuka lewat GOTO
    expect("GOTO \"Cari HP\" (modul biasa)", lk.request(T["GOTO"], s("Cari HP")), 0)
    lk.request(T["GOTO"], s("lokana"))


def test_v053(lk, expect):
    """v0.5.3: TEXT_SLOT, SETTINGS boot_guide, GOTO Panduan."""
    lk.request(T["HELLO"], p_hello("lokana_link.py test"))
    info = lk.wait_frame(lambda f: f[0] == T["DEVICE_INFO"], 1.0)
    caps = parse_device_info(info[2])["caps"] if info else 0
    expect("DEVICE_INFO caps TEXT_SLOT", bool(caps >> CAPS.index("TEXT_SLOT") & 1), True)

    # boot_guide
    lk.frames.clear()
    lk.request(T["SETTINGS"], p_settings_get())
    r = lk.wait_frame(lambda f: f[0] == T["SETTINGS"], 1.0)
    orig = parse_settings(r[2]).get("boot_guide") if r else None
    expect("REPORT berisi boot_guide", orig is not None, True)

    def guide(v):
        lk.frames.clear()
        lk.request(T["SETTINGS"], p_settings_set(boot_guide=v))
        r = lk.wait_frame(lambda f: f[0] == T["SETTINGS"], 1.0)
        return parse_settings(r[2]).get("boot_guide") if r else None
    expect("boot_guide 0", guide(0), 0, raw=True)
    expect("boot_guide 1", guide(1), 1, raw=True)
    guide(orig if orig is not None else 1)

    # TEXT_SLOT: simpan ke slot 8 lewat CUSTOM_TEXT, baca kembali, tampilkan
    before = list_text_slots(lk)
    expect("TEXT_SLOT LIST: 8 slot", len(before), 8, raw=True)
    old8 = before.get(8)
    expect("CUSTOM_TEXT simpan slot 8", lk.request(T["CUSTOM_TEXT"], p_text("Uji slot|delapan", style=2, size=2, slot=8, font=3)), 0)
    it = list_text_slots(lk).get(8)
    expect("TEXT_SLOT slot 8 terbaca", (it["text"], it["style"], it["size"], it["font"]) if it else None,
           ("Uji slot\ndelapan", 2, 2, 3), raw=True)
    expect("TEXT_SLOT SHOW slot 8", lk.request(T["TEXT_SLOT"], struct.pack("<BBH", 2, 8, 3)), 0)
    time.sleep(0.3)
    shown = _capture(lk)
    lk.request(T["CUSTOM_TEXT"], p_text("Uji slot|delapan", style=0, size=2, font=3))
    time.sleep(0.3)
    expect("SHOW slot 8 = teks dengan font Serif", shown == _capture(lk), True)
    lk.request(T["SCREEN"], bytes([SC["INPUT"], 1]))
    expect("CUSTOM_TEXT hapus slot 8", lk.request(T["CUSTOM_TEXT"], p_text("", slot=8)), 0)
    expect("TEXT_SLOT SHOW slot kosong", lk.request(T["TEXT_SLOT"], struct.pack("<BBH", 2, 8, 0)), 6)
    expect("TEXT_SLOT SHOW slot 9", lk.request(T["TEXT_SLOT"], struct.pack("<BBH", 2, 9, 0)), 2)
    expect("TEXT_SLOT SHOW tanpa slot", lk.request(T["TEXT_SLOT"], bytes([2])), 2)
    expect("TEXT_SLOT ITEM dari host", lk.request(T["TEXT_SLOT"], bytes([1, 1, 0, 0, 0, 0])), 2)
    expect("TEXT_SLOT op 7 (belum ada)", lk.request(T["TEXT_SLOT"], bytes([7])), 4)
    expect("TEXT_SLOT payload kosong", lk.request(T["TEXT_SLOT"], b""), 2)
    if old8 and old8["text"]:                              # kembalikan isi slot 8 semula
        lk.request(T["CUSTOM_TEXT"], p_text(old8["text"].replace("\n", "|"), style=old8["style"], size=old8["size"],
                                            slot=8, font=old8["font"]))

    # Panduan: modul tersembunyi yang boleh dibuka lewat GOTO; tap = kembali
    lk.request(T["GOTO"], s("lokana"))
    time.sleep(1.2)
    expect("GOTO \"Panduan\"", lk.request(T["GOTO"], s("panduan")), 0)
    time.sleep(3.5)                                        # kartu ke-2 (TAP): ada kaki "sentuh: lewati"
    d = _capture(lk)
    expect("Panduan tampil (baris kaki terisi)", any(d[56 * 16:64 * 16]), True)
    lk.request(T["SCREEN"], bytes([SC["INPUT"], 1]))
    time.sleep(0.3)
    expect("tap = Panduan selesai", any(_capture(lk)[56 * 16:64 * 16]), False)
    expect("GOTO \"Splash\" tetap ditolak", lk.request(T["GOTO"], s("splash")), 6)


def test_v05(lk, expect):
    """Pesan v0.5: NOTIF, CALL."""
    lk.request(T["HELLO"], p_hello("lokana_link.py test"))
    info = lk.wait_frame(lambda f: f[0] == T["DEVICE_INFO"], 1.0)
    caps = parse_device_info(info[2])["caps"] if info else 0
    expect("DEVICE_INFO caps NOTIF", bool(caps & 1), True)
    expect("NOTIF baru (pesan)", lk.request(T["NOTIF"], p_notif(0x51, "WhatsApp", "Ibu", "Sudah makan? Jangan lupa istirahat ya.")), 0)
    time.sleep(0.5)
    expect("NOTIF id sama = diperbarui", lk.request(T["NOTIF"], p_notif(0x51, "WhatsApp", "Ibu", "2 pesan baru")), 0)
    long_body = "Isi panjang " * 30
    expect("NOTIF isi > 160 byte (dipotong device)", lk.request(T["NOTIF"], p_notif(0x52, "Gmail", "Laporan", long_body, 2, silent=True)), 0)
    expect("NOTIF huruf non-ASCII", lk.request(T["NOTIF"], p_notif(0x53, "Telegram", "Café ☕", "Halo 👋", silent=True)), 0)
    for i in range(10):                                  # lebih dari 8: yang terlama dibuang
        lk.request(T["NOTIF"], p_notif(0x100 + i, "Uji", f"Notif {i}", "isi", silent=True), retries=1)
    expect("NOTIF ke-10 berturut-turut (maks 8 disimpan)", lk.request(T["NOTIF"], p_notif(0x200, "Uji", "Terakhir", "ok", silent=True)), 0)
    expect("NOTIF hapus id ada", lk.request(T["NOTIF"], p_notif_delete(0x200)), 0)
    expect("NOTIF hapus id tidak ada", lk.request(T["NOTIF"], p_notif_delete(0xDEAD)), 0)
    expect("NOTIF terpotong (tanpa body)", lk.request(T["NOTIF"], struct.pack("<BIBB", 0, 9, 1, 0) + s("App")), 2)
    expect("NOTIF op 5 (belum ada)", lk.request(T["NOTIF"], struct.pack("<BI", 5, 1)), 4)
    expect("GOTO Notif", lk.request(T["GOTO"], s("notif")), 0)
    time.sleep(1.0)
    expect("CALL berdering", lk.request(T["CALL"], p_call(True, "Ibu")), 0)
    time.sleep(1.5)
    expect("CALL selesai", lk.request(T["CALL"], p_call(False)), 0)
    expect("CALL state 3 (belum ada)", lk.request(T["CALL"], bytes([3])), 4)
    expect("CALL payload kosong", lk.request(T["CALL"], b""), 2)
    expect("GOTO modul sistem (Panggilan)", lk.request(T["GOTO"], s("Panggilan")), 6)
    for i in list(range(10)) + [0x51 - 0x100, 0x52 - 0x100, 0x53 - 0x100]:
        lk.request(T["NOTIF"], p_notif_delete(0x100 + i), ack=False)
    lk.poll(0.3)


def test_v04(lk, expect, a):
    """Pesan v0.4: SETTINGS, DICE, BUTTON, FIND_PHONE, BITMAP."""
    # DEVICE_INFO memuat kemampuan baru
    lk.request(T["HELLO"], p_hello("lokana_link.py test"))
    info = lk.wait_frame(lambda f: f[0] == T["DEVICE_INFO"], 1.0)
    caps = parse_device_info(info[2])["caps"] if info else 0
    for c in ("DICE", "FIND_PHONE", "BITMAP"):
        expect(f"DEVICE_INFO caps {c}", bool(caps >> CAPS.index(c) & 1), True)

    # SETTINGS GET -> ACK + REPORT
    lk.frames.clear()
    expect("SETTINGS GET", lk.request(T["SETTINGS"], p_settings_get()), 0)
    rep_ = lk.wait_frame(lambda f: f[0] == T["SETTINGS"], 1.0)
    expect("SETTINGS REPORT dikirim", rep_ is not None, True)
    orig = parse_settings(rep_[2]) if rep_ else {}
    expect("REPORT berisi semua key", all(k in orig for k in SETTING_KEYS), True)

    # SET lalu periksa REPORT; nilai asli dikembalikan di akhir
    lk.frames.clear()
    st = lk.request(T["SETTINGS"], p_settings_set(screen_timeout=50, device_name="Uji Lokana", button_events=1))
    expect("SETTINGS SET timeout 50 dtk + nama + button_events", st, 0)
    rep_ = lk.wait_frame(lambda f: f[0] == T["SETTINGS"], 1.0)
    d = parse_settings(rep_[2]) if rep_ else {}
    expect("timeout 50 dibulatkan ke 60", d.get("screen_timeout"), 60, raw=True)
    expect("nama tersimpan", d.get("device_name"), "Uji Lokana", raw=True)
    expect("button_events nyala", d.get("button_events"), 1, raw=True)
    lk.request(T["HELLO"], p_hello("lokana_link.py test"))
    info = lk.wait_frame(lambda f: f[0] == T["DEVICE_INFO"], 1.0)
    expect("DEVICE_INFO memakai nama baru", parse_device_info(info[2])["device_name"] if info else None, "Uji Lokana", raw=True)
    lk.frames.clear()
    lk.request(T["SETTINGS"], p_settings_get())
    rep_ = lk.wait_frame(lambda f: f[0] == T["SETTINGS"], 1.0)
    expect("HELLO baru mematikan button_events", parse_settings(rep_[2]).get("button_events") if rep_ else None, 0, raw=True)
    expect("SETTINGS item terpotong", lk.request(T["SETTINGS"], bytes([1, 0x01, 5, 2])), 2)
    expect("SETTINGS op REPORT dari host", lk.request(T["SETTINGS"], bytes([2])), 2)
    expect("SETTINGS op 9 (belum ada)", lk.request(T["SETTINGS"], bytes([9])), 4)
    expect("SETTINGS key 0x7F (tidak dikenal) diabaikan", lk.request(T["SETTINGS"], bytes([1, 0x7F, 1, 1])), 0)
    if orig:
        restore = {k: orig[k] for k in ("brightness", "sound", "screen_timeout", "flip", "device_name", "notif_popup", "boot_guide")}
        expect("SETTINGS dikembalikan ke nilai awal", lk.request(T["SETTINGS"], p_settings_set(**restore)), 0)
    lk.poll(0.3)

    # DICE: minta lempar -> ACK, lalu hasil setelah animasi
    for name, count, lo, hi in (("d20", 1, 1, 20), ("2d6", 2, 1, 6), ("koin", 1, 0, 1)):
        lk.frames.clear()
        st = lk.request(T["DICE"], p_dice(DICE.index(name)))
        f = lk.wait_frame(lambda f: f[0] == T["DICE"], 2.5)
        d = parse_dice(f[2]) if f else {}
        good = (st == 0 and d.get("op") == 1 and d.get("dice") == DICE.index(name)
                and len(d.get("values", [])) == count and all(lo <= v <= hi for v in d["values"]))
        expect(f"DICE {name} -> hasil {d.get('values')}", good, True)
    expect("DICE ID 50 (belum ada)", lk.request(T["DICE"], p_dice(50)), 4)
    expect("DICE op hasil dari host", lk.request(T["DICE"], bytes([1, 0, 1, 3])), 2)

    # FIND_PHONE dari host: hanya op 0 (HP sudah ditemukan)
    expect("FIND_PHONE op 0 dari host", lk.request(T["FIND_PHONE"], bytes([0])), 0)
    expect("FIND_PHONE op 1 dari host", lk.request(T["FIND_PHONE"], bytes([1])), 2)

    # BITMAP
    w, h, data = demo_bitmap("senyum")
    expect("BITMAP 128x64 tampil 2 dtk (1034 B)", lk.request(T["BITMAP"], p_bitmap(0, 0, 2, 0, 0, w, h, data)), 0)
    w2, h2, data2 = demo_bitmap("hati", 40, 32)
    expect("BITMAP 40x32 (baris 5 byte) ke slot 8",
           lk.request(T["BITMAP"], p_bitmap(1, 8, 0, 44, 16, w2, h2, data2)), 0)
    expect("BITMAP hapus slot 8 (w=0)", lk.request(T["BITMAP"], p_bitmap(1, 8, 0, 0, 0, 0, 0, b"")), 0)
    expect("BITMAP slot 9", lk.request(T["BITMAP"], p_bitmap(1, 9, 0, 0, 0, 8, 1, b"\xff")), 2)
    expect("BITMAP lebar 129", lk.request(T["BITMAP"], p_bitmap(0, 0, 0, 0, 0, 129, 1, bytes(17))), 2)
    expect("BITMAP data kurang", lk.request(T["BITMAP"], p_bitmap(0, 0, 0, 0, 0, 128, 64, bytes(1000))), 2)
    expect("BITMAP op 7 (belum ada)", lk.request(T["BITMAP"], p_bitmap(7, 0, 0, 0, 0, 8, 1, b"\xff")), 4)
    time.sleep(2.2)

    # BUTTON: perlu sentuhan sungguhan (console 'tap' mengakhiri sesi USB)
    if a.touch:
        lk.request(T["SETTINGS"], p_settings_set(button_events=1))
        lk.frames.clear()
        print("  >> Sentuh Lokana sekali dalam 10 detik...")
        f = lk.wait_frame(lambda f: f[0] == T["BUTTON"], 10.0)
        expect("BUTTON terkirim saat disentuh", f is not None, True)
        lk.request(T["SETTINGS"], p_settings_set(button_events=0))


def cmd_test(a):
    """Uji otomatis semua pesan v0.3 + v0.4 lewat USB."""
    lk = Link(a.port, verbose=a.verbose)
    results = []

    def expect(label, got, want, raw=False):
        """raw=True: bandingkan nilai biasa (bukan status ACK)."""
        good = got == want
        def name(v):
            if raw or isinstance(v, str):
                return repr(v)
            if v is None:
                return "tanpa ACK"
            if isinstance(v, bool):
                return "ya" if v else "tidak"
            return STATUS[v] if v < len(STATUS) else str(v)
        results.append(good)
        print(f"  {'LULUS' if good else 'GAGAL'}  {label}: {name(got)}" + ("" if good else f" (harusnya {name(want)})"))

    print("Uji Lokana Link lewat USB:")
    st = lk.request(T["HELLO"], p_hello("lokana_link.py test"))
    expect("HELLO", st, 0)
    info = lk.wait_frame(lambda f: f[0] == T["DEVICE_INFO"], 1.0)
    expect("DEVICE_INFO dikirim setelah HELLO", info is not None, True)
    if info:
        d = parse_device_info(info[2])
        print(f"         {d['device_name']} fw {d['fw_version']} layar {d['screen_w']}x{d['screen_h']}")

    expect("TIME_SYNC", lk.request(T["TIME_SYNC"], p_time()), 0)
    expect("TIME_SYNC epoch tidak masuk akal", lk.request(T["TIME_SYNC"], p_time(1000, 480)), 2)
    expect("EXPRESSION senang 1500 ms", lk.request(T["EXPRESSION"], p_expr(1, 1500)), 0)
    expect("EXPRESSION tanpa hold_ms (field akhir opsional)", lk.request(T["EXPRESSION"], bytes([5])), 0)
    expect("EXPRESSION ID 200 (belum ada)", lk.request(T["EXPRESSION"], p_expr(200)), 4)
    expect("EXPRESSION payload kosong", lk.request(T["EXPRESSION"], b""), 2)
    expect("GOTO Jam", lk.request(T["GOTO"], s("jam")), 0)
    time.sleep(0.5)
    expect("GOTO modul tidak ada", lk.request(T["GOTO"], s("tidakada")), 6)
    expect("GOTO modul sistem (Pairing)", lk.request(T["GOTO"], s("Pairing")), 6)
    expect("CUSTOM_TEXT diam 2 dtk", lk.request(T["CUSTOM_TEXT"], p_text("Halo dari PC!", duration=2)), 0)
    time.sleep(0.8)
    expect("CUSTOM_TEXT slot 9 (tidak ada)", lk.request(T["CUSTOM_TEXT"], p_text("x", slot=9)), 2)
    expect("CUSTOM_TEXT terpotong", lk.request(T["CUSTOM_TEXT"], bytes([0, 0, 0])), 2)
    expect("FIND_KEYS mulai 3 dtk", lk.request(T["FIND_KEYS"], p_find(True, 3)), 0)
    time.sleep(1.0)
    expect("FIND_KEYS berhenti", lk.request(T["FIND_KEYS"], p_find(False)), 0)
    expect("NAV (dikenal, belum didukung v0.5)", lk.request(T["NAV"], b"\x00"), 4)
    expect("type 0x7E (tidak dikenal)", lk.request(0x7E, b"abc"), 1)
    expect("payload 1200 B (batas maks) diterima utuh", lk.request(T["NAV"], bytes(1200)), 4)
    big = lk.request(0x30, bytes(1300))
    expect("payload 1300 B (> 1200)", big, 2)

    # CRC salah -> dibuang tanpa balasan
    seq = lk.next_seq()
    bad = bytearray(envelope(frame(T["EXPRESSION"], seq, p_expr(2))))
    bad[-1] ^= 0xFF
    lk.write_raw(bytes(bad))
    f = lk.wait_frame(lambda f: f[0] == T["ACK"] and f[1] == seq, 1.0)
    expect("CRC salah dibuang tanpa ACK", f is None, True)

    # Frame tanpa seq -> tanpa ACK
    seq_before = len([f for f in lk.frames if f[0] == T["ACK"]])
    lk.request(T["EXPRESSION"], p_expr(0), ack=False)
    lk.poll(0.5)
    expect("seq=0 tidak dibalas ACK", len([f for f in lk.frames if f[0] == T["ACK"]]) == seq_before, True)

    # Frame dikirim terpotong-potong (byte demi byte) tetap tersusun
    seq = lk.next_seq()
    for b in envelope(frame(T["EXPRESSION"], seq, p_expr(1))):
        lk.write_raw(bytes([b]))
        time.sleep(0.002)
    f = lk.wait_frame(lambda f: f[0] == T["ACK"] and f[1] == seq, 2.0)
    expect("frame dikirim per byte", f[2][1] if f else None, 0)

    test_v04(lk, expect, a)
    test_v05(lk, expect)
    test_v05b(lk, expect)
    test_v05c(lk, expect)
    test_v052(lk, expect)
    test_v053(lk, expect)

    # Console teks tetap jalan di port yang sama
    lk.text.clear()
    lk.write_raw(b"info\r\n")
    lk.poll(1.0)
    expect("console 'info' di antara frame", b"Lokana OS" in lk.text, True)

    # Setelah ada perintah console, pesan tanpa diminta (hasil dadu) tidak dikirim lagi lewat USB
    lk.frames.clear()
    expect("DICE setelah console", lk.request(T["DICE"], p_dice(0)), 0)
    f = lk.wait_frame(lambda f: f[0] == T["DICE"], 2.5)
    expect("hasil DICE tidak dikirim setelah console dipakai", f is None, True)
    lk.request(T["HELLO"], p_hello("lokana_link.py test"))
    lk.wait_frame(lambda f: f[0] == T["DEVICE_INFO"], 1.0)
    lk.request(T["DICE"], p_dice(0))
    f = lk.wait_frame(lambda f: f[0] == T["DICE"], 2.5)
    expect("hasil DICE kembali dikirim setelah HELLO ulang", f is not None, True)

    lk.request(T["GOTO"], s("lokana"))
    lk.close()
    n_ok = sum(results)
    print(f"\n{n_ok}/{len(results)} lulus")
    return 0 if n_ok == len(results) else 1


def main():
    ap = argparse.ArgumentParser(description="Penguji Lokana Link v1 lewat USB serial")
    ap.add_argument("--port", help="port serial, contoh COM9 (default: cari VID 303A)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("selftest", help="cek CRC & contoh byte spesifikasi (tanpa device)")
    sub.add_parser("hello", help="HELLO -> DEVICE_INFO")
    t = sub.add_parser("time", help="TIME_SYNC dari jam PC")
    t.add_argument("--tz", type=int, help="selisih zona waktu (menit), contoh 480 = WITA")
    t = sub.add_parser("text", help="CUSTOM_TEXT ('|' = baris baru)")
    t.add_argument("text")
    t.add_argument("--style", default="diam", choices=sorted(STYLES))
    t.add_argument("--size", type=int, default=0, choices=[0, 1, 2, 3])
    t.add_argument("--duration", type=int, default=0, help="detik, 0 = sampai disentuh")
    t.add_argument("--slot", type=int, default=0, help="1-8 = simpan; teks kosong = hapus slot")
    t.add_argument("--font", choices=list(FONTS), help="font Lokana (firmware 0.5.2+)")
    t = sub.add_parser("expr", help="EXPRESSION: " + " ".join(EXPRESSIONS))
    t.add_argument("expr")
    t.add_argument("--hold", type=int, default=0, help="ms, 0 = default 4000")
    t = sub.add_parser("goto", help="GOTO modul (lokana, jam, dadu, teks)")
    t.add_argument("module")
    t = sub.add_parser("find", help="FIND_KEYS")
    t.add_argument("--duration", type=int, default=30)
    t.add_argument("--stop", action="store_true")
    t = sub.add_parser("settings", help="SETTINGS: tanpa opsi = baca, dengan opsi = ubah")
    t.add_argument("--brightness", type=int, choices=[0, 1, 2])
    t.add_argument("--sound", help="on/off")
    t.add_argument("--timeout", type=int, help="layar mati (detik), 0 = tidak pernah")
    t.add_argument("--flip", help="on/off")
    t.add_argument("--name", help="nama Bluetooth, maks 26 byte UTF-8; \"\" = nama bawaan")
    t.add_argument("--notif-popup", type=int, help="lama popup notifikasi (detik), 0 = tidak muncul")
    t.add_argument("--boot-guide", help="on/off: Panduan cara pakai setelah splash boot (firmware 0.5.3+)")
    t = sub.add_parser("textslots", help="TEXT_SLOT: daftar slot teks, atau tampilkan satu slot (--show)")
    t.add_argument("--show", type=int, help="slot 1-8 yang ditampilkan sekarang")
    t.add_argument("--duration", type=int, default=0, help="detik, 0 = sampai disentuh")
    t = sub.add_parser("dice", help="DICE: " + " ".join(DICE) + " (kosong = jenis aktif)")
    t.add_argument("dice", nargs="?")
    t = sub.add_parser("bitmap", help="BITMAP: gambar bawaan atau file gambar")
    t.add_argument("--demo", default="senyum", choices=["senyum", "hati", "catur"])
    t.add_argument("--image", help="file gambar (PNG/JPG), diperkecil ke 128x64; butuh Pillow")
    t.add_argument("--invert", action="store_true", help="balik hitam/putih (untuk --image)")
    t.add_argument("--slot", type=int, default=0, help="1-8 = simpan ke slot, 0 = tampilkan")
    t.add_argument("--duration", type=int, default=0, help="detik, 0 = sampai disentuh")
    t.add_argument("--x", type=int)
    t.add_argument("--y", type=int)
    sub.add_parser("listen", help="dengarkan hasil dadu, tombol (BUTTON), cari HP")
    t = sub.add_parser("notif", help="NOTIF: notifikasi uji")
    t.add_argument("app", nargs="?", default="WhatsApp")
    t.add_argument("title", nargs="?", default="Ibu")
    t.add_argument("body", nargs="?", default="Sudah makan?")
    t.add_argument("--id", type=int, default=1)
    t.add_argument("--category", default="pesan", choices=sorted(NOTIF_CATEGORIES))
    t.add_argument("--silent", action="store_true")
    t.add_argument("--important", action="store_true")
    t.add_argument("--delete", type=int, metavar="ID", help="hapus notifikasi dengan id ini")
    t = sub.add_parser("anim", help="ANIM: animasi bawaan atau GIF")
    t.add_argument("--demo", default="bola", choices=["bola", "denyut", "kedip"])
    t.add_argument("--gif", help="file GIF (butuh Pillow), maks 16 bingkai")
    t.add_argument("--slot", type=int, default=0, help="1-8 = simpan, 0 = tampilkan sekarang")
    t.add_argument("--ms", type=int, default=100, help="ms per bingkai (demo)")
    t.add_argument("--loops", type=int, default=0, help="0 = berulang terus")
    t.add_argument("--duration", type=int, default=0, help="detik tampil (slot 0), 0 = sampai disentuh")
    sub.add_parser("gallery", help="lihat isi slot gambar 1-8")
    t = sub.add_parser("screen", help="SCREEN: layar Lokana langsung / screenshot")
    t.add_argument("--fps", type=int, default=5)
    t.add_argument("--shot", help="simpan screenshot PNG ke file ini (butuh Pillow)")
    t = sub.add_parser("press", help="SCREEN INPUT: gestur jarak jauh")
    t.add_argument("gesture", choices=sorted(GESTURE_ID))
    t = sub.add_parser("call", help="CALL: panggilan masuk")
    t.add_argument("caller", nargs="?")
    t.add_argument("--stop", action="store_true", help="panggilan selesai")
    t = sub.add_parser("test", help="uji otomatis semua pesan v0.3 - v0.5")
    t.add_argument("-v", "--verbose", action="store_true", help="tampilkan semua frame & log")
    t.add_argument("--touch", action="store_true", help="ikut uji BUTTON (perlu menyentuh Lokana)")
    sub.add_parser("monitor", help="tampilkan log & frame dari device")

    a = ap.parse_args()
    handlers = {
        "selftest": cmd_selftest,
        "hello": cmd_hello,
        "time": simple("TIME_SYNC", lambda a: p_time(tz_min=a.tz)),
        "text": simple("CUSTOM_TEXT", lambda a: p_text(a.text, STYLES[a.style], a.size, a.duration, a.slot,
                                                      FONTS[a.font] if a.font else None)),
        "expr": simple("EXPRESSION", lambda a: p_expr(expr_id(a.expr), a.hold)),
        "goto": simple("GOTO", lambda a: s(a.module)),
        "find": simple("FIND_KEYS", lambda a: p_find(not a.stop, a.duration)),
        "settings": cmd_settings,
        "textslots": cmd_textslots,
        "dice": cmd_dice,
        "bitmap": cmd_bitmap,
        "listen": cmd_listen,
        "notif": cmd_notif,
        "call": cmd_call,
        "anim": cmd_anim,
        "gallery": cmd_gallery,
        "screen": cmd_screen,
        "press": cmd_press,
        "test": cmd_test,
        "monitor": cmd_monitor,
    }
    sys.exit(handlers[a.cmd](a))


if __name__ == "__main__":
    main()
