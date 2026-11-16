// Codec Lokana Link: byte harus sama persis dengan spesifikasi, skrip Python
// (protocol/tools/lokana_link.py), dan balasan asli dari firmware 0.4.0.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:lokana/link/proto.dart';

String hex(List<int> b) => b.map((v) => v.toRadixString(16).padLeft(2, '0')).join(' ');
Uint8List bytes(String h) => Uint8List.fromList(h.split(' ').map((s) => int.parse(s, radix: 16)).toList());

void main() {
  test('TIME_SYNC contoh spesifikasi bag. 10', () {
    final w = Writer()..u32(1794798000)..i16(480);
    expect(hex(w.done()), 'b0 71 fa 6a e0 01');
  });

  test('CUSTOM_TEXT "Halo" (contoh nRF Connect)', () {
    expect(hex(pCustomText('Halo')), '00 00 00 00 00 04 48 61 6c 6f');
  });

  test('EXPRESSION senang 1500 ms', () {
    expect(hex(pExpression(1, holdMs: 1500)), '01 dc 05');
  });

  test('SETTINGS SET sama dengan skrip Python', () {
    expect(hex(pSettingsSet(brightness: 2, screenTimeoutS: 60, deviceName: 'Hai', buttonEvents: true)),
        '01 01 01 02 03 02 3c 00 05 03 48 61 69 06 01 01');
  });

  test('DICE d20', () => expect(hex(pDice(6)), '00 06'));

  test('BITMAP 9x2 di (44,-2) ke slot 3', () {
    final b = Bitmap1(9, 2);
    b.data.setAll(0, [0xff, 0x80, 0x01, 0x00]);
    expect(hex(pBitmap(b, op: 1, slot: 3, durationS: 10, x: 44, y: -2)), '01 03 0a 00 2c 00 fe ff 09 02 ff 80 01 00');
  });

  test('Bitmap1: MSB = piksel kiri, baris dibulatkan ke byte', () {
    final b = Bitmap1(9, 2)..set(0, 0, true)..set(8, 0, true)..set(7, 1, true);
    expect(b.stride, 2);
    expect(hex(b.data), '80 80 01 00');
    expect(b.get(8, 0), isTrue);
    expect(b.get(1, 0), isFalse);
  });

  test('DEVICE_INFO dari firmware 0.4.0', () {
    final d = DeviceInfo.parse(bytes('01 01 05 30 2e 34 2e 30 80 00 40 00 ff 05 30 0e 00 00 0a 55 6a 69 20 4c 6f 6b 61 6e 61'));
    expect(d.fwVersion, '0.4.0');
    expect(d.screenW, 128);
    expect(d.screenH, 64);
    expect(d.batteryText, 'USB');
    expect(d.has(Caps.dice), isTrue);
    expect(d.has(Caps.findPhone), isTrue);
    expect(d.has(Caps.bitmap), isTrue);
    expect(d.has(Caps.notif), isFalse);
    expect(d.name, 'Uji Lokana');
  });

  test('SETTINGS REPORT dari firmware 0.4.0', () {
    final s = LokanaSettings.parse(bytes('02 01 01 01 02 01 01 03 02 3c 00 04 01 00 05 0a 55 6a 69 20 4c 6f 6b 61 6e 61 06 01 00'));
    expect(s.brightness, 1);
    expect(s.sound, isTrue);
    expect(s.screenTimeoutS, 60);
    expect(s.flip, isFalse);
    expect(s.deviceName, 'Uji Lokana');
    expect(s.buttonEvents, isFalse);
  });

  test('SETTINGS REPORT dengan nama kosong', () {
    final s = LokanaSettings.parse(bytes('02 05 00 01 01 02'));
    expect(s.deviceName, '');
    expect(s.brightness, 2);
  });

  test('DICE hasil 2d6 dari firmware', () {
    final r = DiceResult.parse(bytes('01 01 02 02 05'))!;
    expect(r.typeName, '2d6');
    expect(r.values, [2, 5]);
    expect(r.text, '2 + 5 = 7');
    expect(DiceResult.parse(bytes('01 07 01 00'))!.text, 'Angka');
  });

  test('Teks ke ASCII OLED', () {
    expect(toLokanaAscii('Café “Lokana” – ok'), 'Cafe "Lokana" - ok');
    expect(toLokanaAscii('Hai 👋'), 'Hai ?');
    expect(toLokanaAscii('❤️'), '?');
    expect(hasUnsupportedChars('Apa?'), isFalse);
    expect(hasUnsupportedChars('Hai 👋'), isTrue);
  });
}
