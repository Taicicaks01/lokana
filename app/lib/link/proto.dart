// Lokana Link v1: nomor type, status, dan codec payload.
// Sumber kebenaran: protocol/LOKANA_LINK.md
// Framing, seq, dan ACK ada di sisi Kotlin (BleLink.kt).
import 'dart:convert';
import 'dart:typed_data';

class T {
  static const hello = 0x00, timeSync = 0x01, deviceInfo = 0x02, settings = 0x03, ack = 0x05, unpair = 0x06;
  static const notif = 0x10, call = 0x15;
  static const findKeys = 0x20, findPhone = 0x21, expression = 0x22, dice = 0x23, goto = 0x24, button = 0x25;
  static const customText = 0x30, bitmap = 0x31, anim = 0x32, screen = 0x33;
}

/// Status ACK. Nilai negatif dari sisi Kotlin: -1 tanpa ACK, -2 tidak tersambung.
class Status {
  static const ok = 0, unknownType = 1, badPayload = 2, busy = 3, notSupported = 4, notAllowed = 5, error = 6;
  static const noAck = -1, notConnected = -2;

  static String describe(int s) => switch (s) {
        ok => 'OK',
        unknownType => 'Pesan tidak dikenal Lokana',
        badPayload => 'Data tidak valid',
        busy => 'Lokana sedang sibuk',
        notSupported => 'Belum didukung firmware Lokana ini',
        notAllowed => 'Tidak diizinkan',
        error => 'Gagal di Lokana',
        noAck => 'Lokana tidak menjawab',
        notConnected => 'Lokana belum tersambung',
        _ => 'Status $s',
      };
}

class Caps {
  static const notif = 1 << 0, customText = 1 << 4, bitmap = 1 << 5, buzzer = 1 << 9;
  static const dice = 1 << 10, findPhone = 1 << 11, anim = 1 << 12, screen = 1 << 13;
}

/// ID ekspresi = urutan enum Expression di firmware. Jangan diurutkan ulang.
const expressions = <(String, String)>[
  ('netral', '😐'), ('senang', '😊'), ('sedih', '😢'), ('marah', '😠'), ('ngantuk', '😴'),
  ('kaget', '😮'), ('cinta', '😍'), ('pusing', '😵'), ('curiga', '🤨'), ('bosan', '😒'),
  ('semangat', '🤩'), ('gugup', '😬'), ('kedip', '😉'),
];

/// ID dadu sesuai spesifikasi DICE.
const diceTypes = ['1d6', '2d6', 'd4', 'd8', 'd10', 'd12', 'd20', 'Koin'];

class Writer {
  final _b = BytesBuilder();
  void u8(int v) => _b.addByte(v & 0xFF);
  void u16(int v) { u8(v); u8(v >> 8); }
  void i16(int v) => u16(v & 0xFFFF);
  void u32(int v) { u16(v & 0xFFFF); u16(v >> 16); }
  void str(String s, {int max = 255}) {
    var b = utf8.encode(s);
    if (b.length > max) b = b.sublist(0, max);
    u8(b.length);
    _b.add(b);
  }
  void bytes(List<int> d) => _b.add(d);
  Uint8List done() => _b.toBytes();
}

class Reader {
  final Uint8List p;
  int i = 0;
  Reader(this.p);
  bool get has => i < p.length;
  int u8() => i < p.length ? p[i++] : 0;
  int u16() => u8() | u8() << 8;
  int u32() => u16() | u16() << 16;
  String str() {
    final n = u8();
    final end = (i + n).clamp(0, p.length);
    final s = utf8.decode(p.sublist(i, end), allowMalformed: true);
    i = end;
    return s;
  }
}

// ---------------- Payload H->D ----------------
Uint8List pTimeSync(DateTime now) {
  final w = Writer()
    ..u32(now.millisecondsSinceEpoch ~/ 1000)
    ..i16(now.timeZoneOffset.inMinutes);
  return w.done();
}

Uint8List pExpression(int id, {int holdMs = 0}) => (Writer()..u8(id)..u16(holdMs)).done();

Uint8List pDice(int dice) => (Writer()..u8(0)..u8(dice)).done();

Uint8List pGoto(String module) => (Writer()..str(module)).done();

Uint8List pFindKeys(bool on, {int seconds = 30}) => (Writer()..u8(on ? 1 : 0)..u8(seconds)).done();

Uint8List pFindPhone(bool ring) => (Writer()..u8(ring ? 1 : 0)).done();

/// style: 0 diam, 1 berjalan, 2 berkedip. size 0 = otomatis. slot 0 = tampilkan sekarang.
Uint8List pCustomText(String text, {int style = 0, int size = 0, int durationS = 0, int slot = 0}) =>
    (Writer()
          ..u8(style)
          ..u8(size)
          ..u16(durationS)
          ..u8(slot)
          ..str(toLokanaAscii(text), max: 200))
        .done();

Uint8List pBitmap(Bitmap1 b, {int op = 0, int slot = 0, int durationS = 0, int x = 0, int y = 0}) =>
    (Writer()
          ..u8(op)
          ..u8(slot)
          ..u16(durationS)
          ..i16(x)
          ..i16(y)
          ..u8(b.w)
          ..u8(b.h)
          ..bytes(b.data))
        .done();

/// Hapus slot gambar 1-8 (BITMAP op 1 dengan w = h = 0).
Uint8List pBitmapDelete(int slot) => (Writer()..u8(1)..u8(slot)..u16(0)..i16(0)..i16(0)..u8(0)..u8(0)).done();

Uint8List pSettingsGet() => Uint8List.fromList([0]);

/// Nama Bluetooth: UTF-8 apa adanya (boleh Dewanagari), dipotong maks 26 byte di batas huruf.
List<int> bleNameBytes(String name) {
  final out = <int>[];
  for (final r in name.runes) {
    if (r < 0x20 || r == 0x7F) continue;
    final b = utf8.encode(String.fromCharCode(r));
    if (out.length + b.length > 26) break;
    out.addAll(b);
  }
  return out;
}

Uint8List pSettingsSet({int? brightness, bool? sound, int? screenTimeoutS, bool? flip, String? deviceName,
    bool? buttonEvents}) {
  final w = Writer()..u8(1);
  void item(int key, List<int> v) { w.u8(key); w.u8(v.length); w.bytes(v); }
  if (brightness != null) item(0x01, [brightness]);
  if (sound != null) item(0x02, [sound ? 1 : 0]);
  if (screenTimeoutS != null) item(0x03, [screenTimeoutS & 0xFF, screenTimeoutS >> 8 & 0xFF]);
  if (flip != null) item(0x04, [flip ? 1 : 0]);
  if (deviceName != null) item(0x05, bleNameBytes(deviceName));
  if (buttonEvents != null) item(0x06, [buttonEvents ? 1 : 0]);
  return w.done();
}

// ---------------- ANIM (animasi bingkai) ----------------
class AnimOp {
  static const begin = 0, frame = 1, end = 2, abort = 3, read = 4, list = 5, listReport = 6, delete = 7, show = 8;
}

/// Animasi 1-bit: semua bingkai berukuran w x h. Gambar diam = 1 bingkai.
class Anim1 {
  final int w, h;
  final List<Bitmap1> frames;
  int frameMs, loops;
  Anim1(this.w, this.h, this.frames, {this.frameMs = 100, this.loops = 0});
  int get frameBytes => ((w + 7) >> 3) * h;
  int get totalBytes => frameBytes * frames.length;
  static const maxBytes = 16384, maxFrames = 32;
  bool get fits => frames.isNotEmpty && frames.length <= maxFrames && totalBytes <= maxBytes;
}

Uint8List pAnimBegin(Anim1 a, {int slot = 0, int durationS = 0, int? x, int? y}) => (Writer()
      ..u8(AnimOp.begin)
      ..u8(slot)
      ..u8(a.frames.length)
      ..u16(a.frameMs)
      ..u8(a.loops)
      ..u16(durationS)
      ..i16(x ?? (128 - a.w) ~/ 2)
      ..i16(y ?? (64 - a.h) ~/ 2)
      ..u8(a.w)
      ..u8(a.h))
    .done();

Uint8List pAnimFrame(int index, Bitmap1 b) => (Writer()..u8(AnimOp.frame)..u8(index)..bytes(b.data)).done();
Uint8List pAnimOp(int op, [List<int> args = const []]) => Uint8List.fromList([op, ...args]);
Uint8List pAnimShow(int slot, {int durationS = 0}) => (Writer()..u8(AnimOp.show)..u8(slot)..u16(durationS)).done();

/// Isi galeri dari LIST_REPORT: (bingkai, w, h) untuk slot 1-8; bingkai 0 = kosong.
List<(int, int, int)> parseAnimList(Uint8List p) =>
    [for (var i = 0; i < 8; i++) if (1 + 3 * i + 2 < p.length) (p[1 + 3 * i], p[2 + 3 * i], p[3 + 3 * i]) else (0, 0, 0)];

/// Penyusun animasi dari BEGIN / FRAME / END yang dikirim device (balasan READ).
class AnimAssembler {
  int w = 0, h = 0, count = 0, frameMs = 100, loops = 0;
  final _frames = <int, Bitmap1>{};

  /// Masukkan payload ANIM. Mengembalikan animasi lengkap saat END diterima.
  Anim1? feed(Uint8List p) {
    if (p.isEmpty) return null;
    final r = Reader(p)..u8();
    switch (p[0]) {
      case AnimOp.begin:
        r.u8();
        count = r.u8();
        frameMs = r.u16();
        loops = r.u8();
        r.u16(); r.u16(); r.u16();               // duration, x, y
        w = r.u8();
        h = r.u8();
        _frames.clear();
      case AnimOp.frame:
        final i = r.u8();
        final b = Bitmap1(w, h);
        final n = b.data.length.clamp(0, p.length - 2);
        b.data.setRange(0, n, p, 2);
        _frames[i] = b;
      case AnimOp.end:
        if (w == 0 || h == 0) return null;
        final list = [for (var i = 0; i < count; i++) _frames[i] ?? Bitmap1(w, h)];
        return Anim1(w, h, list, frameMs: frameMs, loops: loops);
    }
    return null;
  }
}

// ---------------- SCREEN (layar langsung + remote) ----------------
class ScreenOp {
  static const start = 0, stop = 1, frame = 2, input = 3, capture = 4;
}

/// Gestur untuk SCREEN INPUT (sama dengan tombol fisik).
class Gestures {
  static const tap = 1, double = 2, triple = 3, hold = 4;
}

Uint8List pScreenStart(int maxFps) => Uint8List.fromList([ScreenOp.start, maxFps]);
Uint8List pScreenOp(int op) => Uint8List.fromList([op]);
Uint8List pScreenInput(int gesture) => Uint8List.fromList([ScreenOp.input, gesture]);

class ScreenFrame {
  final bool screenOn;
  final Bitmap1 bitmap;
  ScreenFrame(this.screenOn, this.bitmap);

  static ScreenFrame? parse(Uint8List p) {
    if (p.length < 4 || p[0] != ScreenOp.frame) return null;
    final b = Bitmap1(p[2], p[3]);
    final n = b.data.length.clamp(0, p.length - 4);
    b.data.setRange(0, n, p, 4);
    return ScreenFrame(p[1] & 1 != 0, b);
  }
}

// ---------------- Payload D->H ----------------
class DeviceInfo {
  final int protoVer, deviceType, screenW, screenH, battery, flags, caps;
  final String fwVersion, name;
  DeviceInfo(this.protoVer, this.deviceType, this.fwVersion, this.screenW, this.screenH, this.battery, this.flags,
      this.caps, this.name);

  factory DeviceInfo.parse(Uint8List p) {
    final r = Reader(p);
    final ver = r.u8(), type = r.u8();
    final fw = r.str();
    final w = r.u16(), h = r.u16(), bat = r.u8(), flags = r.u8(), caps = r.u32();
    return DeviceInfo(ver, type, fw, w, h, bat, flags, caps, r.str());
  }

  bool has(int cap) => caps & cap != 0;
  bool get usbPower => flags & 1 != 0;
  String get batteryText => battery == 255 ? (usbPower ? 'USB' : '?') : '$battery%';
}

class LokanaSettings {
  int brightness = 1, screenTimeoutS = 60;
  bool sound = true, flip = false, buttonEvents = false;
  String deviceName = '';

  static LokanaSettings parse(Uint8List p) {
    final s = LokanaSettings();
    final r = Reader(p)..u8();               // op = 2 REPORT
    while (r.i + 2 <= p.length) {
      final key = r.u8(), n = r.u8();
      final v = p.sublist(r.i, (r.i + n).clamp(0, p.length));
      r.i += n;
      if (v.isEmpty && key != 0x05) continue;
      switch (key) {
        case 0x01: s.brightness = v[0];
        case 0x02: s.sound = v[0] != 0;
        case 0x03: s.screenTimeoutS = v.length >= 2 ? v[0] | v[1] << 8 : v[0];
        case 0x04: s.flip = v[0] != 0;
        case 0x05: s.deviceName = utf8.decode(v, allowMalformed: true);
        case 0x06: s.buttonEvents = v[0] != 0;
      }
    }
    return s;
  }
}

class DiceResult {
  final int dice;
  final List<int> values;
  final DateTime at;
  DiceResult(this.dice, this.values) : at = DateTime.now();

  static DiceResult? parse(Uint8List p) {
    if (p.length < 3 || p[0] != 1) return null;
    final n = p[2].clamp(0, p.length - 3);
    return DiceResult(p[1], p.sublist(3, 3 + n));
  }

  String get typeName => dice < diceTypes.length ? diceTypes[dice] : 'dadu $dice';
  bool get isCoin => dice == 7;
  String get text => isCoin
      ? (values.isNotEmpty && values[0] == 0 ? 'Angka' : 'Gambar')
      : values.length == 2
          ? '${values[0]} + ${values[1]} = ${values[0] + values[1]}'
          : values.join(', ');
}

// ---------------- Bitmap 1-bit ----------------
/// Format spesifikasi: baris demi baris, tiap baris dibulatkan ke byte, MSB = piksel paling kiri.
class Bitmap1 {
  final int w, h;
  final Uint8List data;
  Bitmap1(this.w, this.h) : data = Uint8List(((w + 7) >> 3) * h);
  int get stride => (w + 7) >> 3;
  bool get(int x, int y) => data[y * stride + (x >> 3)] & (0x80 >> (x & 7)) != 0;
  void set(int x, int y, bool on) {
    final i = y * stride + (x >> 3), m = 0x80 >> (x & 7);
    data[i] = on ? data[i] | m : data[i] & ~m;
  }
}

// ---------------- Teks ----------------
const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ù': 'u',
  'ú': 'u', 'û': 'u', 'ü': 'u', 'ñ': 'n', 'ç': 'c', 'ý': 'y', 'ÿ': 'y',
  '‘': "'", '’': "'", '“': '"', '”': '"', '–': '-', '—': '-', '…': '...',
};

/// Font OLED hanya ASCII: huruf beraksen diganti padanannya, sisanya jadi '?'.
String toLokanaAscii(String s) {
  final out = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    if (r == 10 || (r >= 32 && r < 127)) {
      out.write(ch);
    } else {
      final lower = ch.toLowerCase();
      final rep = _accents[lower];
      if (rep != null) {
        out.write(ch == lower ? rep : rep.toUpperCase());
      } else if (r == 0xFE0F || r == 0x200D) {
        // penanda emoji, lewati
      } else {
        out.write('?');
      }
    }
  }
  return out.toString();
}

/// true jika teks punya karakter yang tidak bisa ditampilkan font OLED (emoji dll.)
bool hasUnsupportedChars(String s) => '?'.allMatches(toLokanaAscii(s)).length > '?'.allMatches(s).length;
