// Pratinjau ekspresi Lokana: wajah 128×64 digambar dengan geometri yang sama dengan firmware
// (firmware/src/core/face.cpp: preset(), drawEye(), heart(), spiral(), aksen) lalu dijadikan bitmap 1-bit.
// Dipakai halaman Ekspresi & thumbnail Studio, menggantikan emoji (DESIGN.md §6).
import 'dart:math';
import 'package:material_ui/material_ui.dart';
import 'link/proto.dart';
import 'oled_fonts.dart';
import 'render.dart';

class _Shape {
  double w = 24, h = 26, r = 7;
  final lidTop = [0.0, 0.0], slant = [0.0, 0.0], lidBot = [0.0, 0.0], scale = [1.0, 1.0];
}

// Layar 128×64 (lihat face.cpp)
const double _sx = 1.45, _sy = 1.6, _gap = 20, _cy = 29;

/// ID = urutan enum Expression firmware (lihat `expressions` di proto.dart).
_Shape _preset(int e) {
  final p = _Shape();
  void both(List<double> l, double v) => l..[0] = v..[1] = v;
  switch (e) {
    case 1: p.w = 26; p.h = 24; p.r = 9; both(p.lidBot, 0.55);                                   // senang
    case 2: p.h = 22; both(p.lidTop, 0.30); both(p.slant, -0.6);                                  // sedih
    case 3: p.h = 22; p.r = 5; both(p.lidTop, 0.25); both(p.slant, 0.8);                          // marah
    case 4: p.w = 26; both(p.lidTop, 0.62); both(p.slant, -0.15);                                 // ngantuk
    case 5: p.w = 20; p.h = 30; p.r = 10;                                                         // kaget
    case 8: p.lidTop..[0] = 0.5..[1] = 0.18; p.slant..[0] = 0.25..[1] = 0.1; p.scale[0] = 0.92;   // curiga
    case 9: p.w = 28; p.r = 4; both(p.lidTop, 0.5);                                               // bosan
    case 10: p.w = 28; p.h = 28; p.r = 9; both(p.lidBot, 0.5);                                    // semangat
    case 11: p.w = 20; p.h = 22; both(p.lidTop, 0.12); both(p.slant, -0.35);                      // gugup
    case 12: p.lidBot[1] = 0.6; p.lidTop[1] = 0.15;                                               // kedip
  }
  p.w *= _sx; p.h *= _sy; p.r *= _sx;
  return p;
}

void _paintFace(Canvas g, int e) {
  final on = Paint()..color = Colors.white;
  final off = Paint()..color = Colors.black;
  final p = _preset(e);
  final ecx = [0.0, 0.0], ecy = [0.0, 0.0], ew = [0.0, 0.0];
  for (var i = 0; i < 2; i++) {
    final dir = i == 0 ? -1.0 : 1.0;
    final sc = p.scale[i];
    final w = p.w * sc, h = p.h * sc;
    ecx[i] = 64 + dir * (_gap / 2 + p.w / 2);
    ecy[i] = _cy;
    ew[i] = w;
    if (e == 6) {                                           // cinta: hati
      final r = max(2.0, (9 * _sx * 0.5).floorToDouble());
      final cx = ecx[i].roundToDouble(), cy = ecy[i].roundToDouble();
      g.drawCircle(Offset(cx - r, cy - r / 2), r, on);
      g.drawCircle(Offset(cx + r, cy - r / 2), r, on);
      g.drawPath(
          Path()
            ..moveTo(cx - 2 * r, cy - r / 2)
            ..lineTo(cx + 2 * r, cy - r / 2)
            ..lineTo(cx, cy + 1.7 * r)
            ..close(),
          on);
      continue;
    }
    if (e == 7) {                                           // pusing: spiral
      const t = 5 * pi;
      final rmax = 11 * _sy;
      final line = Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      var px = ecx[i], py = ecy[i];
      for (var a = 0.4; a < t; a += 0.4) {
        final r = rmax * a / t, x = ecx[i] + cos(a + dir * 0.3) * r, y = ecy[i] + sin(a + dir * 0.3) * r;
        g.drawLine(Offset(px, py), Offset(x, y), line);
        px = x;
        py = y;
      }
      continue;
    }
    // drawEye()
    final iw = max(4, w.round()).toDouble(), ih = max(2, h.round()).toDouble();
    final x0 = (ecx[i] - w / 2).roundToDouble(), y0 = (ecy[i] - h / 2).roundToDouble();
    final r = min((p.r * sc).roundToDouble(), min((ih / 2).floorToDouble(), (iw / 2).floorToDouble()));
    g.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x0, y0, iw, ih), Radius.circular(r)), on);
    final lt = p.lidTop[i], sl = p.slant[i];
    if (lt > 0.01 || sl.abs() > 0.01) {                     // kelopak atas miring
      final base = y0 + lt * ih, half = sl * ih * 0.5;
      final yIn = (base + half).truncateToDouble(), yOut = (base - half).truncateToDouble();
      final yL = i == 0 ? yOut : yIn, yR = i == 0 ? yIn : yOut;
      final top = y0 - 2, xl = x0 - 1, xr = x0 + iw;
      g.drawPath(
          Path()
            ..moveTo(xl, top)
            ..lineTo(xr, top)
            ..lineTo(xr, yR)
            ..lineTo(xl, yL)
            ..close(),
          off);
    }
    final lb = p.lidBot[i];
    if (lb > 0.01) {                                        // pipi bawah -> mata senyum
      final by = (y0 + ih - lb * ih).truncateToDouble(), bw = iw + 6;
      g.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x0 - 3, by, bw, ih + 4), Radius.circular(min(bw / 2 - 1, (ih + 4) / 2))),
          off);
    }
  }

  // ---------- Aksen (bingkai diam) ----------
  void drop(double x, double y, double r) {
    g.drawCircle(Offset(x, y), r, on);
    g.drawPath(Path()..moveTo(x - r, y)..lineTo(x + r, y)..lineTo(x, y - 2 * r)..close(), on);
  }
  if (e == 2) drop(ecx[0] - ew[0] / 2 - 6, 34, 3);           // sedih: air mata
  if (e == 11) drop(ecx[1] + ew[1] / 2 + 6, 18, 3);          // gugup: keringat
  if (e == 1 || e == 6 || e == 10) {                         // pipi merona: 3 garis miring
    final line = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.3;
    for (var i = 0; i < 2; i++) {
      const len = 4.0, step = 5.0, w = 2 * step + len;
      final x0 = (i == 0 ? ecx[i] - ew[i] / 2 - 1 : ecx[i] + ew[i] / 2 + 1 - w).truncateToDouble();
      final y0 = (ecy[i] + p.h * 0.28).truncateToDouble();
      for (var s = 0; s < 3; s++) {
        g.drawLine(Offset(x0 + s * step, y0), Offset(x0 + s * step + len - 1, y0 - len), line);
      }
    }
  }
}

/// Tulis karakter font piksel bawaan (glcdfont) ke bitmap, seperti Adafruit_GFX::drawChar.
void _glyph(Bitmap1 b, int x, int y, int c, int size) {
  for (var i = 0; i < 5; i++) {
    var line = glcdFont[c * 5 + i];
    for (var j = 0; j < 8; j++, line >>= 1) {
      if (line & 1 == 0) continue;
      for (var dy = 0; dy < size; dy++) {
        for (var dx = 0; dx < size; dx++) {
          final px = x + i * size + dx, py = y + j * size + dy;
          if (px >= 0 && py >= 0 && px < b.w && py < b.h) b.set(px, py, true);
        }
      }
    }
  }
}

final _cache = <int, Future<Bitmap1>>{};

/// Wajah Lokana untuk ekspresi [id] (0..12), bitmap 128×64.
Future<Bitmap1> expressionFace(int id) => _cache[id] ??= () async {
      final b = await rasterize(128, 64, (c) => _paintFace(c, id), threshold: 128);
      if (id == 4) {                                        // ngantuk: z kecil & Z besar
        _glyph(b, 108, 24, 'z'.codeUnitAt(0), 1);
        _glyph(b, 112, 12, 'Z'.codeUnitAt(0), 2);
      }
      return b;
    }();
