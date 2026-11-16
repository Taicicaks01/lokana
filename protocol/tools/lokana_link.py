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
  python lokana_link.py test                     # uji otomatis semua pesan v0.3
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
T = dict(HELLO=0x00, TIME_SYNC=0x01, DEVICE_INFO=0x02, SETTINGS=0x03, OTA=0x04, ACK=0x05,
         NOTIF=0x10, NAV=0x11, PC_STATS=0x12, MEETING=0x13, PHONE_STATS=0x14, CALL=0x15,
         FIND_KEYS=0x20, FIND_PHONE=0x21, EXPRESSION=0x22, DICE=0x23, GOTO=0x24, BUTTON=0x25,
         CUSTOM_TEXT=0x30, BITMAP=0x31, WIFI_PROV=0x40, WIFI_STATUS=0x41)
TYPE_NAME = {v: k for k, v in T.items()}
STATUS = ["OK", "UNKNOWN_TYPE", "BAD_PAYLOAD", "BUSY", "NOT_SUPPORTED", "NOT_ALLOWED", "ERROR"]
EXPRESSIONS = ["netral", "senang", "sedih", "marah", "ngantuk", "kaget", "cinta",
               "pusing", "curiga", "bosan", "semangat", "gugup", "kedip"]
CAPS = ["NOTIF", "NAV", "PC_STATS", "PHONE_STATS", "CUSTOM_TEXT", "BITMAP", "OTA", "WIFI",
        "HID", "BUZZER", "DICE", "FIND_PHONE"]
STYLES = {"diam": 0, "static": 0, "scroll": 1, "jalan": 1, "blink": 2, "kedip": 2}
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


def p_text(text, style=0, size=0, duration=0, slot=0):
    return struct.pack("<BBHB", style, size, duration, slot) + s(text.replace("|", "\n"))


def p_expr(expr, hold=0):
    return struct.pack("<BH", expr, hold)


def p_find(on=True, duration=30):
    return bytes([1 if on else 0, duration])


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


def describe(type_, seq, payload) -> str:
    name = TYPE_NAME.get(type_, f"0x{type_:02X}")
    if type_ == T["ACK"] and len(payload) >= 2:
        st = STATUS[payload[1]] if payload[1] < len(STATUS) else payload[1]
        return f"ACK seq={seq} untuk {TYPE_NAME.get(payload[0], hex(payload[0]))}: {st}"
    if type_ == T["DEVICE_INFO"]:
        d = parse_device_info(payload)
        caps = [c for b, c in enumerate(CAPS) if d["caps"] >> b & 1]
        flags = [f for b, f in enumerate(["USB", "WiFi", "bonded"]) if d["flags"] >> b & 1]
        bat = "?" if d["battery_pct"] == 255 else f'{d["battery_pct"]}%'
        return (f'DEVICE_INFO: {d["device_name"]} fw {d["fw_version"]} proto {d["proto_ver"]} '
                f'layar {d["screen_w"]}x{d["screen_h"]} baterai {bat} flags {flags} caps {caps}')
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


def cmd_test(a):
    """Uji otomatis semua pesan v0.3 lewat USB."""
    lk = Link(a.port, verbose=a.verbose)
    results = []

    def expect(label, got, want):
        good = got == want
        def name(v):
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
    expect("NOTIF (dikenal, belum didukung v0.3)", lk.request(T["NOTIF"], b"\x00"), 4)
    expect("type 0x7E (tidak dikenal)", lk.request(0x7E, b"abc"), 1)
    expect("payload 1200 B (batas maks) diterima utuh", lk.request(T["NOTIF"], bytes(1200)), 4)
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

    # Console teks tetap jalan di port yang sama
    lk.text.clear()
    lk.write_raw(b"info\r\n")
    lk.poll(1.0)
    expect("console 'info' di antara frame", b"Lokana OS" in lk.text, True)

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
    t = sub.add_parser("expr", help="EXPRESSION: " + " ".join(EXPRESSIONS))
    t.add_argument("expr")
    t.add_argument("--hold", type=int, default=0, help="ms, 0 = default 4000")
    t = sub.add_parser("goto", help="GOTO modul (lokana, jam, dadu, teks)")
    t.add_argument("module")
    t = sub.add_parser("find", help="FIND_KEYS")
    t.add_argument("--duration", type=int, default=30)
    t.add_argument("--stop", action="store_true")
    t = sub.add_parser("test", help="uji otomatis semua pesan v0.3")
    t.add_argument("-v", "--verbose", action="store_true", help="tampilkan semua frame & log")
    sub.add_parser("monitor", help="tampilkan log & frame dari device")

    a = ap.parse_args()
    handlers = {
        "selftest": cmd_selftest,
        "hello": cmd_hello,
        "time": simple("TIME_SYNC", lambda a: p_time(tz_min=a.tz)),
        "text": simple("CUSTOM_TEXT", lambda a: p_text(a.text, STYLES[a.style], a.size, a.duration, a.slot)),
        "expr": simple("EXPRESSION", lambda a: p_expr(expr_id(a.expr), a.hold)),
        "goto": simple("GOTO", lambda a: s(a.module)),
        "find": simple("FIND_KEYS", lambda a: p_find(not a.stop, a.duration)),
        "test": cmd_test,
        "monitor": cmd_monitor,
    }
    sys.exit(handlers[a.cmd](a))


if __name__ == "__main__":
    main()
