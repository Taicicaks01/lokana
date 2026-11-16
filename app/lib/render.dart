// Emoji / teks -> bitmap 1-bit untuk pesan BITMAP. Digambar oleh HP (font & emoji sistem),
// karena font OLED Lokana hanya ASCII.
import 'dart:math';
import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'link/proto.dart';

/// Gambar [content] sebesar mungkin di kanvas w x h (latar hitam), lalu ubah ke 1-bit.
/// Piksel menyala jika kecerahannya >= [threshold] (0-255). [invert] membalik hasil.
Future<Bitmap1> renderToBitmap(String content,
    {int w = 128, int h = 64, int threshold = 110, bool invert = false, bool bold = true}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = Colors.black);
  final tp = TextPainter(
    text: TextSpan(
      text: content,
      style: TextStyle(
          fontSize: 200, color: Colors.white, height: 1.0, fontWeight: bold ? FontWeight.w800 : FontWeight.w400),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout();
  const pad = 2.0;
  final scale = min((w - pad * 2) / tp.width, (h - pad * 2) / tp.height);
  c.translate((w - tp.width * scale) / 2, (h - tp.height * scale) / 2);
  c.scale(scale);
  tp.paint(c, Offset.zero);
  final img = await rec.endRecording().toImage(w, h);
  final bd = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  img.dispose();
  tp.dispose();
  final out = Bitmap1(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final lum = 0.299 * bd.getUint8(i) + 0.587 * bd.getUint8(i + 1) + 0.114 * bd.getUint8(i + 2);
      out.set(x, y, (lum >= threshold) != invert);
    }
  }
  return out;
}

/// Pratinjau layar OLED: piksel menyala berwarna biru muda di atas hitam, seperti aslinya.
class OledPreview extends StatelessWidget {
  final Bitmap1? bitmap;
  final int screenW, screenH;
  const OledPreview({super.key, this.bitmap, this.screenW = 128, this.screenH = 64});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: screenW / screenH,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24, width: 2),
        ),
        padding: const EdgeInsets.all(6),
        child: CustomPaint(painter: _OledPainter(bitmap, screenW, screenH)),
      ),
    );
  }
}

class _OledPainter extends CustomPainter {
  final Bitmap1? b;
  final int sw, sh;
  _OledPainter(this.b, this.sw, this.sh);

  @override
  void paint(Canvas canvas, Size size) {
    final bm = b;
    if (bm == null) return;
    final px = size.width / sw;
    final p = Paint()..color = const Color(0xFF9EE7FF);
    final ox = (sw - bm.w) ~/ 2, oy = (sh - bm.h) ~/ 2;
    for (var y = 0; y < bm.h; y++) {
      for (var x = 0; x < bm.w; x++) {
        if (bm.get(x, y)) canvas.drawRect(Rect.fromLTWH((ox + x) * px, (oy + y) * px, px * 0.9, px * 0.9), p);
      }
    }
  }

  @override
  bool shouldRepaint(_OledPainter old) => old.b != b;
}
