// Pratinjau teks di aplikasi harus sama persis dengan layar Lokana.
// fixtures/oled_text.json = tangkapan SCREEN CAPTURE asli dari firmware 0.5.3 (USB, 2026-11-17).
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lokana/oled_text.dart';

String ascii(List<int> d) {
  final b = StringBuffer();
  for (var y = 0; y < 64; y++) {
    for (var x = 0; x < 128; x++) {
      b.write(d[y * 16 + (x >> 3)] & (0x80 >> (x & 7)) != 0 ? '#' : '.');
    }
    b.writeln();
  }
  return b.toString();
}

void main() {
  final cases = jsonDecode(File('test/fixtures/oled_text.json').readAsStringSync()) as List;
  for (final c in cases) {
    test('Teks "${(c['text'] as String).replaceAll('\n', '|')}" ukuran ${c['size']} font ${c['font']}', () {
      final hex = c['bitmap'] as String;
      final want = [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
      final got = OledTextLayout(c['text'] as String, size: c['size'] as int, font: c['font'] as int).draw(0).data;
      expect(ascii(got), ascii(want));
    });
  }
}
