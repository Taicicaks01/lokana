// Pratinjau modul Teks Lokana di HP, piksel demi piksel sama dengan firmware:
// tata letak & animasi meniru firmware/src/modules/text_module.cpp + core/text_wrap.h (wrapTextPx),
// gambar huruf meniru Adafruit_GFX::drawChar (font di oled_fonts.dart).
import 'dart:math';
import 'link/proto.dart';
import 'oled_fonts.dart';

class OledMetrics {
  final GfxFont? f;
  final int scale, lineH, asc;
  const OledMetrics(this.f, this.scale, this.lineH, this.asc);
}

class OledTextLayout {
  static const maxLines = 28;
  final String text;
  final int style, w, h;
  final OledMetrics m;
  final List<(int, int)> lines;   // (awal, panjang)
  final bool vscroll;
  /// Ukuran yang benar-benar dipakai (1-3), berguna untuk "Otomatis".
  final int sizeUsed;

  OledTextLayout._(this.text, this.style, this.w, this.h, this.m, this.lines, this.vscroll, this.sizeUsed);

  static List<int>? _glyph(GfxFont f, int c) {
    if (c < f.first || c > f.last) c = 0x3F;   // '?'
    final i = (c - f.first) * 6;
    return f.glyphs.sublist(i, i + 6);         // offset, w, h, xAdvance, xOffset, yOffset
  }

  static OledMetrics _metrics(int font, int size) {
    final f = font >= 1 && font <= gfxFonts.length ? gfxFonts[font - 1][size - 1] : null;
    if (f == null) return OledMetrics(null, size, 8 * size, 7 * size);
    final asc = -_glyph(f, 0x41)![5];
    final g = _glyph(f, 0x67)!;
    return OledMetrics(f, 1, asc + g[2] + g[5] + 2, asc);
  }

  static int _charW(OledMetrics m, int c) => m.f != null ? _glyph(m.f!, c)![3] : 6 * m.scale;

  int textW(int start, int len) {
    var px = 0;
    for (var i = start; i < start + len && i < text.length; i++) {
      px += _charW(m, text.codeUnitAt(i));
    }
    return px;
  }

  static List<(int, int)> _wrap(String t, int maxW, int Function(int) cw) {
    final out = <(int, int)>[];
    final len = t.length;
    var s = 0;
    while (s <= len && out.length < maxLines) {
      var e = s, sp = -1, px = 0;
      while (e < len && t.codeUnitAt(e) != 10) {
        final c = cw(t.codeUnitAt(e));
        if (px + c > maxW && e > s) break;
        if (t.codeUnitAt(e) == 32) sp = e;
        px += c;
        e++;
      }
      if (e >= len || t.codeUnitAt(e) == 10) {
        out.add((s, e - s));
        if (e >= len) break;
        s = e + 1;
      } else if (t.codeUnitAt(e) == 32) {
        out.add((s, e - s));
        s = e + 1;
      } else if (sp > s) {
        out.add((s, sp - s));
        s = sp + 1;
      } else {
        out.add((s, e - s));
        s = e;
      }
    }
    return out;
  }

  /// [text] sudah ASCII (lihat toLokanaAscii). [size] 0 = otomatis, [font] 0 = piksel.
  factory OledTextLayout(String text, {int style = 0, int size = 0, int font = 0, int w = 128, int h = 64}) {
    if (font > 4) font = 0;
    if (style > 2) style = 0;
    if (size > 3) size = 0;
    final maxSz = font != 0 ? 3 : (h >= 64 ? 3 : 2);
    if (style == 1) {
      final t = text.replaceAll('\n', ' ');
      final sz = size != 0 ? size : maxSz;
      return OledTextLayout._(t, style, w, h, _metrics(font, sz), const [], false, sz);
    }
    var sz = size != 0 ? size : maxSz;
    late OledMetrics m;
    late List<(int, int)> lines;
    for (;; sz--) {
      m = _metrics(font, sz);
      final mm = m;
      lines = _wrap(text, w - 2, (c) => _charW(mm, c));
      if (size != 0 || sz == 1 || lines.length * m.lineH <= h + 2) break;
    }
    return OledTextLayout._(text, style, w, h, m, lines, lines.length * m.lineH > h + 2, sz);
  }

  /// Panjang satu putaran animasi (ms); 0 = diam.
  int get cycleMs {
    if (style == 1) return (textW(0, text.length) + w) * 12;
    if (style == 2) return 1000;
    if (vscroll) return 1500 * 2 + (lines.length * m.lineH - h + 2) * 45;
    return 0;
  }

  /// Gambar layar pada waktu [t] ms sejak teks tampil.
  Bitmap1 draw(int t) {
    final b = Bitmap1(w, h);
    void px(int x, int y) {
      if (x >= 0 && y >= 0 && x < w && y < h) b.set(x, y, true);
    }

    var cx = 0;
    void write(int c, int cy) {
      final f = m.f;
      if (f == null) {
        final s = m.scale;
        if (!(cx >= w || cy >= h || cx + 6 * s - 1 < 0 || cy + 8 * s - 1 < 0)) {
          for (var i = 0; i < 5; i++) {
            var line = glcdFont[c * 5 + i];
            for (var j = 0; j < 8; j++, line >>= 1) {
              if (line & 1 == 0) continue;
              for (var dy = 0; dy < s; dy++) {
                for (var dx = 0; dx < s; dx++) {
                  px(cx + i * s + dx, cy + j * s + dy);
                }
              }
            }
          }
        }
        cx += 6 * s;
        return;
      }
      if (c < f.first || c > f.last) return;
      final g = _glyph(f, c)!;
      var bo = g[0], bits = 0, bit = 0;
      for (var yy = 0; yy < g[2]; yy++) {
        for (var xx = 0; xx < g[1]; xx++) {
          if (bit++ & 7 == 0) bits = f.bitmap[bo++];
          if (bits & 0x80 != 0) px(cx + g[4] + xx, cy + g[5] + yy);
          bits = (bits << 1) & 0xFF;
        }
      }
      cx += g[3];
    }

    final base = m.f != null ? m.asc : 0;
    if (style == 1) {
      final tw = textW(0, text.length);
      cx = w - (t ~/ 12) % (tw + w);
      final cy = (h - m.asc) ~/ 2 + base;
      for (final c in text.codeUnits) {
        write(c, cy);
      }
      return b;
    }
    if (style == 2 && t % 1000 >= 650) return b;
    final total = lines.length * m.lineH;
    var y0 = (h - total) ~/ 2 + 1;
    if (vscroll) {
      const hold = 1500, pxMs = 45;
      final over = total - h + 2, cycle = hold * 2 + over * pxMs, tt = t % cycle;
      y0 = -(tt < hold ? 0 : min(over, (tt - hold) ~/ pxMs));
    }
    for (var i = 0; i < lines.length; i++) {
      final y = y0 + i * m.lineH;
      if (y <= -m.lineH || y >= h) continue;
      final (s, n) = lines[i];
      cx = (w - textW(s, n)) ~/ 2;
      for (var k = 0; k < n; k++) {
        write(text.codeUnitAt(s + k), y + base);
      }
    }
    return b;
  }

  /// Animasi untuk OledPreview: bingkai tiap [stepMs] sepanjang satu putaran.
  Anim1 toAnim({int stepMs = 50, int maxFrames = 400}) {
    final c = cycleMs;
    if (c == 0) return Anim1(w, h, [draw(0)]);
    final step = max(stepMs, (c / maxFrames).ceil());
    return Anim1(w, h, [for (var t = 0; t < c; t += step) draw(t)], frameMs: step);
  }
}
