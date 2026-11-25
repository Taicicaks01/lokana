"""Koneksi USB ke Lokana untuk Lokana Desktop.

Memakai fungsi protokol dari protocol/tools/lokana_link.py (frame, CRC, payload) yang sudah teruji,
tapi dengan pengelola koneksi sendiri: mencari Lokana, menyambung ulang, dan tidak pernah keluar program.

Mencari Lokana: semua port USB VID 303A (ESP32) dicoba dengan HELLO; hanya yang membalas DEVICE_INFO
device_type 1 yang dipakai. Port lain (mis. flight controller ESP32-S3) diingat dan tidak dicoba lagi
selama 5 menit. Port dibuka tanpa DTR/RTS supaya board tidak ter-reset.
"""
import os
import sys
import time

import serial
import serial.tools.list_ports

# protocol/tools (saat dijalankan dari repo) atau folder exe (PyInstaller menyertakan modulnya)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "protocol", "tools"))
import lokana_link as L  # noqa: E402

CLIENT_DESKTOP = 3                    # LOKANA_LINK.md HELLO client_type: 3 = Lokana Desktop
RETRY_OTHER_S = 300


def _hello(name):
    return bytes([1, CLIENT_DESKTOP]) + L.s(name)


class LokanaUsb:
    def __init__(self, client_name, preferred_port=None, exclude=(), log=print):
        self.client_name = client_name
        self.preferred = preferred_port
        self.exclude = set(p.upper() for p in exclude)
        self.log = log
        self.ser = None
        self.port = None
        self.info = None
        self._buf = bytearray()
        self._others = {}               # port -> waktu terakhir dicoba (bukan Lokana)

    # ---------- frame ----------
    def _send(self, type_, payload, seq=0):
        self.ser.write(L.envelope(L.frame(type_, seq, payload)))

    def _read_frames(self, timeout):
        """Baca port selama `timeout` detik; hasil daftar (type, seq, payload)."""
        out, end = [], time.time() + timeout
        while True:                     # minimal sekali baca (timeout 0 = buang data yang sudah masuk)
            self._buf += self.ser.read(4096)
            while True:
                i = self._buf.find(b"\xA5\x5A")
                if i < 0:
                    del self._buf[:max(0, len(self._buf) - 1)]
                    break
                del self._buf[:i]
                if len(self._buf) < 6:
                    break
                n = self._buf[4] | self._buf[5] << 8
                if len(self._buf) < 8 + n:
                    break
                fr = bytes(self._buf[2:6 + n])
                crc = self._buf[6 + n] | self._buf[7 + n] << 8
                del self._buf[:8 + n]
                if crc == L.crc16(fr):
                    out.append((fr[0], fr[1], fr[4:]))
            if (out and timeout > 0.2) or time.time() >= end:
                break
        return out

    # ---------- mencari & menyambung ----------
    def _open(self, port):
        s = serial.Serial()
        s.port, s.baudrate, s.timeout = port, 115200, 0.05
        s.dtr = False                   # tanpa DTR/RTS: ESP32 tidak ter-reset
        s.rts = False
        s.open()
        time.sleep(0.5)
        s.dtr = True                    # USB CDC ESP32-C3 baru mengirim setelah DTR
        time.sleep(0.3)
        s.reset_input_buffer()
        return s

    def _probe(self, port):
        try:
            self.ser = self._open(port)
        except Exception as e:
            self.log(f"{port}: tidak bisa dibuka ({e.__class__.__name__})")
            self.ser = None
            return False
        self._buf.clear()
        self._send(L.T["HELLO"], _hello(self.client_name), seq=1)
        for type_, _seq, p in self._read_frames(1.5):
            if type_ == L.T["DEVICE_INFO"]:
                info = L.parse_device_info(p)
                if info.get("device_type") == 1:
                    self.port, self.info = port, info
                    return True
        self.ser.close()
        self.ser = None
        return False

    def connect(self):
        """Cari Lokana. True jika tersambung."""
        ports = [p.device for p in serial.tools.list_ports.comports() if p.vid == 0x303A]
        if self.preferred:
            ports = [self.preferred] + [p for p in ports if p != self.preferred]
        now = time.time()
        for port in ports:
            if port.upper() in self.exclude:
                continue
            if now - self._others.get(port, 0) < RETRY_OTHER_S:
                continue
            if self._probe(port):
                self.log(f"tersambung ke {self.info.get('device_name')} di {port} (Lokana OS {self.info.get('fw_version')})")
                return True
            self._others[port] = now
            self.log(f"{port}: bukan Lokana (tidak membalas HELLO), dilewati {RETRY_OTHER_S // 60} menit")
        return False

    @property
    def connected(self):
        return self.ser is not None

    def supports_stats(self):
        caps = (self.info or {}).get("caps", 0)
        return bool(caps >> L.CAPS.index("PC_STATS") & 1)

    def supports_layout(self):
        """Lokana OS 0.8+: teks nilai, label 10 huruf, dua metrik per baris (bit caps STATS_LAYOUT)."""
        caps = (self.info or {}).get("caps", 0)
        return bool(caps >> L.CAPS.index("STATS_LAYOUT") & 1)

    def close(self):
        if self.ser:
            try:
                self.ser.close()
            except Exception:
                pass
        self.ser = None
        self.port = None

    # ---------- kirim ----------
    def sync_time(self):
        self._send(L.T["TIME_SYNC"], L.p_time())

    def send_stats(self, metrics, texts=None, rows=None):
        """PC_STATS tanpa ACK (seq 0) + buang data masuk (log device) supaya buffer tidak penuh.
        texts/rows (0.8) selalu boleh dikirim: Lokana OS 0.7 mengabaikan byte di belakang daftar metrik."""
        self._send(L.T["PC_STATS"], L.p_pcstats(metrics, texts, rows))
        self._read_frames(0)
