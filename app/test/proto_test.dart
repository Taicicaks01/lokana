// Codec Lokana Link: byte harus sama persis dengan spesifikasi, skrip Python
// (protocol/tools/lokana_link.py), dan balasan asli dari firmware 0.4.0.
import 'dart:convert';
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

  test('SETTINGS notif_popup dan font CUSTOM_TEXT (0.5.2)', () {
    expect(hex(pSettingsSet(notifPopupS: 10)), '01 07 01 0a');
    final s = LokanaSettings.parse(bytes('02 01 01 01 07 01 00'));
    expect(s.notifPopupS, 0);
    expect(LokanaSettings.parse(bytes('02 01 01 01')).notifPopupS, isNull);   // firmware lama
    expect(hex(pCustomText('Hi', font: 3)), '00 00 00 00 00 02 48 69 03');
    expect(hex(pCustomText('Hi')), '00 00 00 00 00 02 48 69');                // tanpa font = format lama
  });

  test('Perbandingan versi firmware', () {
    expect(versionAtLeast('0.5.2', '0.5.2'), isTrue);
    expect(versionAtLeast('0.5.10', '0.5.2'), isTrue);
    expect(versionAtLeast('0.5.1', '0.5.2'), isFalse);
    expect(versionAtLeast('1.0', '0.5.2'), isTrue);
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

  test('ANIM BEGIN / FRAME sama dengan skrip Python', () {
    final a = Anim1(32, 32, List.generate(4, (_) => Bitmap1(32, 32)), frameMs: 150);
    expect(hex(pAnimBegin(a, slot: 8)), '00 08 04 96 00 00 00 00 30 00 10 00 20 20');
    final b = Anim1(128, 64, List.generate(2, (_) => Bitmap1(128, 64)), frameMs: 100, loops: 3);
    expect(hex(pAnimBegin(b, slot: 0, durationS: 10)), '00 00 02 64 00 03 0a 00 00 00 00 00 80 40');
    final f = Bitmap1(24, 1)..data.setAll(0, [1, 2, 3]);
    expect(hex(pAnimFrame(1, f)), '01 01 01 02 03');
    expect(b.fits, isTrue);
    expect(Anim1(128, 64, List.generate(17, (_) => Bitmap1(128, 64))).fits, isFalse);
  });

  test('ANIM: susun ulang balasan READ', () {
    final asm = AnimAssembler();
    expect(asm.feed(bytes('00 03 02 64 00 00 00 00 00 00 00 00 08 02')), isNull);
    asm.feed(bytes('01 01 81 42'));
    asm.feed(bytes('01 00 ff 00'));
    final a = asm.feed(bytes('02'))!;
    expect(a.frames.length, 2);
    expect(hex(a.frames[0].data), 'ff 00');
    expect(hex(a.frames[1].data), '81 42');
    expect(a.frameMs, 100);
  });

  test('Nama Bluetooth UTF-8 (Dewanagari)', () {
    expect(hex(pSettingsSet(deviceName: 'Lokana_लोचन-01')),
        '01 05 16 4c 6f 6b 61 6e 61 5f e0 a4 b2 e0 a5 8b e0 a4 9a e0 a4 a8 2d 30 31');
    final long = bleNameBytes('Lokana_${'लोचन' * 4}');
    expect(long.length <= 26, isTrue);
    expect(utf8.decode(long), startsWith('Lokana_'));       // tidak memutus huruf
  });

  test('SCREEN: START, INPUT, FRAME', () {
    expect(hex(pScreenStart(10)), '00 0a');
    expect(hex(pScreenInput(Gestures.double)), '03 02');
    final f = ScreenFrame.parse(bytes('02 01 10 02 80 00 00 01'))!;
    expect(f.screenOn, isTrue);
    expect(f.bitmap.w, 16);
    expect(f.bitmap.get(0, 0), isTrue);
    expect(f.bitmap.get(15, 1), isTrue);
    expect(f.bitmap.get(1, 0), isFalse);
    expect(ScreenFrame.parse(bytes('02 00 10')), isNull);
  });

  // Byte asli dari firmware 0.5.3 (USB, 2026-11-17)
  test('TEXT_SLOT: LIST, SHOW, ITEM', () {
    expect(hex(pTextSlotList()), '00');
    expect(hex(pTextSlotShow(1, durationS: 3)), '02 01 03 00');
    final s = TextSlot.parse(bytes('01 01 01 03 02 04 48 61 69 21'))!;
    expect((s.slot, s.style, s.size, s.font, s.text), (1, 1, 3, 2, 'Hai!'));
    expect(TextSlot.parse(bytes('01 05 00 00 00 00'))!.isEmpty, isTrue);
    expect(TextSlot.parse(bytes('02 01')), isNull);
  });

  test('SETTINGS boot_guide (0.5.3)', () {
    expect(hex(pSettingsSet(bootGuide: false)), '01 08 01 00');
    expect(LokanaSettings.parse(bytes('02 07 01 06 08 01 01')).bootGuide, isTrue);
    expect(LokanaSettings.parse(bytes('02 07 01 06')).bootGuide, isNull);
  });

  test('Teks ke ASCII OLED', () {
    expect(toLokanaAscii('Café “Lokana” – ok'), 'Cafe "Lokana" - ok');
    expect(toLokanaAscii('Hai 👋'), 'Hai ?');
    expect(toLokanaAscii('❤️'), '?');
    expect(hasUnsupportedChars('Apa?'), isFalse);
    expect(hasUnsupportedChars('Hai 👋'), isTrue);
  });
}
