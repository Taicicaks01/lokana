// Gambar untuk Lokana: emoji/teks/gambar -> bitmap 1-bit (BITMAP / ANIM).
// HP yang menggambar (font & emoji sistem, dekoder GIF Flutter), karena OLED Lokana hanya 1-bit ASCII.
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'link/proto.dart';
import 'theme.dart';

/// Efek animasi untuk emoji/teks.
enum Effect {
  still('Diam', 1),
  pulse('Denyut', 8),
  bounce('Memantul', 8),
  wiggle('Goyang', 8),
  spin('Putar', 12),
  blink('Kedip', 8),
  marquee('Geser', 24);

  final String label;
  final int frames;
  const Effect(this.label, this.frames);
}

/// Gambar [content] (emoji/teks) besar-besar, lalu potong rapat ke piksel yang benar-benar terisi.
/// Kotak baris teks sering lebih kecil dari emoji, jadi tanpa ini gambar bisa terpotong.
Future<ui.Image?> renderGlyph(String content) async {
  const fontSize = 220.0;
  final tp = TextPainter(
    text: TextSpan(
        text: content,
        style: const TextStyle(fontSize: fontSize, color: Colors.white, height: 1.2, fontWeight: FontWeight.w800)),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout();
  const pad = fontSize * 0.4;                      // ruang untuk bagian emoji yang keluar dari kotak baris
  final cw = (tp.width + pad * 2).ceil(), ch = (tp.height + pad * 2).ceil();
  final rec = ui.PictureRecorder();
  tp.paint(Canvas(rec), const Offset(pad, pad));
  final big = await rec.endRecording().toImage(cw, ch);
  tp.dispose();
  final bd = (await big.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  int x0 = cw, y0 = ch, x1 = -1, y1 = -1;
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      if (bd.getUint8((y * cw + x) * 4 + 3) > 24) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) { big.dispose(); return null; }
  final w = x1 - x0 + 1, h = y1 - y0 + 1;
  final rec2 = ui.PictureRecorder();
  Canvas(rec2).drawImageRect(big, Rect.fromLTWH(x0.toDouble(), y0.toDouble(), w.toDouble(), h.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint());
  big.dispose();
  return rec2.endRecording().toImage(w, h);
}

/// Gambar di kanvas w x h berlatar hitam, lalu ubah ke 1-bit.
/// [threshold] 0-255 (kecerahan minimum piksel menyala). [dither] untuk foto (Floyd-Steinberg).
Future<Bitmap1> rasterize(int w, int h, void Function(Canvas c) paint,
    {int threshold = 110, bool invert = false, bool dither = false}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = Colors.black);
  paint(c);
  final img = await rec.endRecording().toImage(w, h);
  final bd = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  img.dispose();
  final lum = Float32List(w * h);
  for (var i = 0; i < w * h; i++) {
    lum[i] = 0.299 * bd.getUint8(i * 4) + 0.587 * bd.getUint8(i * 4 + 1) + 0.114 * bd.getUint8(i * 4 + 2);
  }
  final out = Bitmap1(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final on = lum[i] >= threshold;
      out.set(x, y, on != invert);
      if (dither) {
        final err = lum[i] - (on ? 255 : 0);
        if (x + 1 < w) lum[i + 1] += err * 7 / 16;
        if (y + 1 < h) {
          if (x > 0) lum[i + w - 1] += err * 3 / 16;
          lum[i + w] += err * 5 / 16;
          if (x + 1 < w) lum[i + w + 1] += err * 1 / 16;
        }
      }
    }
  }
  return out;
}

/// Emoji/teks yang sudah dipotong rapat -> animasi dengan efek.
Future<Anim1> animateGlyph(ui.Image g, Effect fx,
    {int w = 128, int h = 64, int frameMs = 100, int threshold = 110, bool invert = false}) async {
  final fit = min(w / g.width, h / g.height);
  final frames = <Bitmap1>[];
  for (var i = 0; i < fx.frames; i++) {
    final t = i / fx.frames;
    double scale = 0.96, angle = 0, dx = 0, dy = 0;
    var visible = true;
    switch (fx) {
      case Effect.still:
        break;
      case Effect.pulse:
        scale = 0.78 + 0.18 * (0.5 + 0.5 * sin(2 * pi * t));
      case Effect.bounce:
        scale = 0.78;
        dy = h * 0.11 - sin(pi * t).abs() * h * 0.22;
      case Effect.wiggle:
        scale = 0.86;
        angle = sin(2 * pi * t) * 0.22;
      case Effect.spin:
        scale = 0.82;
        angle = 2 * pi * t;
      case Effect.blink:
        visible = i < fx.frames - 2;
      case Effect.marquee:
        break;
    }
    frames.add(await rasterize(w, h, (c) {
      if (!visible) return;
      if (fx == Effect.marquee) {
        final s = h / g.height * 0.9;               // setinggi layar, bergeser dari kanan ke kiri
        final span = w + g.width * s;
        c.translate(w - span * t, (h - g.height * s) / 2);
        c.scale(s);
        c.drawImage(g, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
        return;
      }
      final s = fit * scale;
      c.translate(w / 2 + dx, h / 2 + dy);
      c.rotate(angle);
      c.scale(s);
      c.drawImage(g, Offset(-g.width / 2, -g.height / 2), Paint()..filterQuality = FilterQuality.medium);
    }, threshold: threshold, invert: invert));
  }
  return Anim1(w, h, frames, frameMs: fx == Effect.marquee ? max(40, frameMs ~/ 2) : frameMs);
}

/// File gambar / GIF -> animasi (maks [maxFrames], muat dalam batas 16 KB), dipusatkan & dipertahankan rasionya.
Future<Anim1?> decodeImageFile(Uint8List bytes,
    {int screenW = 128, int screenH = 64, int threshold = 128, bool invert = false, bool dither = true}) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final total = codec.frameCount;
  final maxFrames = min(Anim1.maxFrames, Anim1.maxBytes ~/ (((screenW + 7) >> 3) * screenH));
  final step = max(1, (total / maxFrames).ceil());
  final frames = <Bitmap1>[];
  var durMs = 0, picked = 0;
  for (var i = 0; i < total && frames.length < maxFrames; i++) {
    final f = await codec.getNextFrame();
    if (i % step != 0) { f.image.dispose(); continue; }
    durMs += f.duration.inMilliseconds;
    picked++;
    final img = f.image;
    final s = min(screenW / img.width, screenH / img.height);
    frames.add(await rasterize(screenW, screenH, (c) {
      c.translate((screenW - img.width * s) / 2, (screenH - img.height * s) / 2);
      c.scale(s);
      c.drawImage(img, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    }, threshold: threshold, invert: invert, dither: dither));
    img.dispose();
  }
  codec.dispose();
  if (frames.isEmpty) return null;
  final ms = picked > 1 ? max(40, (durMs ~/ picked) * step) : 100;
  return Anim1(screenW, screenH, frames, frameMs: ms);
}

/// Pratinjau layar OLED: piksel menyala biru muda di atas hitam. Animasi diputar sesuai frameMs.
class OledPreview extends StatefulWidget {
  final Anim1? anim;
  final int screenW, screenH;
  const OledPreview({super.key, this.anim, this.screenW = 128, this.screenH = 64});

  @override
  State<OledPreview> createState() => _OledPreviewState();
}

class _OledPreviewState extends State<OledPreview> {
  Timer? _timer;
  int _f = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(OledPreview old) {
    super.didUpdateWidget(old);
    if (old.anim != widget.anim) _start();
  }

  void _start() {
    _timer?.cancel();
    _f = 0;
    final a = widget.anim;
    if (a != null && a.frames.length > 1) {
      _timer = Timer.periodic(Duration(milliseconds: max(40, a.frameMs)), (_) {
        if (mounted) setState(() => _f = (_f + 1) % a.frames.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.anim;
    final b = a == null || a.frames.isEmpty ? null : a.frames[_f % a.frames.length];
    return AspectRatio(
      aspectRatio: widget.screenW / widget.screenH,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24, width: 2),
        ),
        padding: const EdgeInsets.all(6),
        child: CustomPaint(painter: _OledPainter(b, widget.screenW, widget.screenH, AppTheme.instance.oled.color)),
      ),
    );
  }
}

class _OledPainter extends CustomPainter {
  final Bitmap1? b;
  final int sw, sh;
  final Color color;
  _OledPainter(this.b, this.sw, this.sh, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final bm = b;
    if (bm == null) return;
    final px = size.width / sw;
    final p = Paint()..color = color;
    final ox = (sw - bm.w) ~/ 2, oy = (sh - bm.h) ~/ 2;
    for (var y = 0; y < bm.h; y++) {
      for (var x = 0; x < bm.w; x++) {
        if (bm.get(x, y)) canvas.drawRect(Rect.fromLTWH((ox + x) * px, (oy + y) * px, px * 0.9, px * 0.9), p);
      }
    }
  }

  @override
  bool shouldRepaint(_OledPainter old) => old.b != b || old.color != color;
}
