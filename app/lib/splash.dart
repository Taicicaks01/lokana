// Layar pembuka: konsep sama dengan splash boot firmware (firmware/src/modules/splash_module.cpp).
// Garis atas (shirorekha) tumbuh -> huruf लोचन turun dari garis -> matra ो muncul -> LOKANA ->
// kilau -> huruf kembali ke garis -> garis terbelah jadi dua mata terpejam -> mata Lokana terbuka.
// Font Baloo 2 (SIL OFL) dari assets/fonts. Tap = lewati.
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'theme.dart';

const _word = 'लोचन';

// Linimasa (ms), sama dengan firmware sampai T_END; setelahnya mata membuka.
const _tLine = 150, _tDrop = 550, _tHook = 1150, _tTag = 1450, _tGlint = 2000, _tOut = 2900;
const _tEyes = 3250, _tOpen = 3650, _tDone = 4050;

/// Tulisan लोचन yang sudah dirender + posisi garis atasnya (dalam piksel gambar).
class _Art {
  final ui.Image image;
  final double lineTop, lineBottom;
  _Art(this.image, this.lineTop, this.lineBottom);

  static Future<_Art?> build() async {
    final tp = TextPainter(
      text: const TextSpan(
        text: _word,
        style: TextStyle(
          fontFamily: 'Baloo2',
          fontSize: 200,
          height: 1.6,
          color: Colors.white,
          fontVariations: [FontVariation('wght', 700)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width.ceil() + 40, h = tp.height.ceil() + 40;
    final rec = ui.PictureRecorder();
    tp.paint(Canvas(rec), const Offset(20, 20));
    tp.dispose();
    final big = await rec.endRecording().toImage(w, h);
    final bd = (await big.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    bool on(int x, int y) => bd.getUint8((y * w + x) * 4 + 3) > 128;

    // Potong rapat ke tinta
    int x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (on(x, y)) {
          x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y);
        }
      }
    }
    if (x1 < 0) { big.dispose(); return null; }
    final cw = x1 - x0 + 1, ch = y1 - y0 + 1;

    // Garis atas: baris yang terisi >= 75% lebar (sama dengan gen_splash.py)
    int top = -1, bottom = -1;
    for (var y = y0; y <= y1; y++) {
      var n = 0;
      for (var x = x0; x <= x1; x++) {
        if (on(x, y)) n++;
      }
      if (n >= 0.75 * cw) { if (top < 0) top = y - y0; bottom = y - y0; }
    }
    if (top < 0) { top = (ch * 0.29).round(); bottom = (ch * 0.41).round(); }

    final rec2 = ui.PictureRecorder();
    Canvas(rec2).drawImageRect(big, Rect.fromLTWH(x0.toDouble(), y0.toDouble(), cw.toDouble(), ch.toDouble()),
        Rect.fromLTWH(0, 0, cw.toDouble(), ch.toDouble()), Paint());
    big.dispose();
    return _Art(await rec2.endRecording().toImage(cw, ch), top.toDouble(), bottom + 1.0);
  }
}

class LokanaSplash extends StatefulWidget {
  final VoidCallback onDone;
  const LokanaSplash({super.key, required this.onDone});

  @override
  State<LokanaSplash> createState() => _LokanaSplashState();
}

class _LokanaSplashState extends State<LokanaSplash> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  _Art? _art;
  double _t = 0;           // ms sejak tulisan siap
  double _skipFrom = -1;   // waktu saat dilewati (langsung ke penutup)
  bool _haptic = false, _done = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _Art.build().then((a) {
      if (!mounted) return;
      if (a == null) return _finish();
      setState(() => _art = a);
      _ticker.start();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());   // aksesibilitas: tanpa animasi
    }
  }

  void _tick(Duration d) {
    var t = d.inMicroseconds / 1000.0;
    if (_skipFrom >= 0) t = _tOut + (t - _skipFrom);
    if (!_haptic && t >= _tHook && _skipFrom < 0) {
      _haptic = true;
      HapticFeedback.lightImpact();
    }
    setState(() => _t = t);
    if (t >= _tDone) _finish();
  }

  /// Lewati: waktu ticker saat ini dipetakan ke awal penutup (huruf kembali ke garis).
  void _skip() {
    if (_skipFrom >= 0 || _t >= _tOut) return;
    _skipFrom = _t;
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _ticker.stop();
    widget.onDone();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _art?.image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: ColoredBox(
        color: Colors.black,
        child: SizedBox.expand(
          child: _art == null
              ? null
              : CustomPaint(painter: _SplashPainter(_art!, _t, AppTheme.instance.oled.color)),
        ),
      ),
    );
  }
}

double _phase(double t, int a, int b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
double _easeOut(double p) => 1 - pow(1 - p, 3).toDouble();
double _easeInOut(double p) => p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2;
double _easeOutBack(double p) {
  const c = 1.7;
  final q = p - 1;
  return 1 + (c + 1) * q * q * q + c * q * q;
}

class _SplashPainter extends CustomPainter {
  final _Art art;
  final double t;
  final Color color;
  _SplashPainter(this.art, this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (t < _tLine) return;
    final img = art.image;
    final aw = min(size.width * 0.62, 320.0);
    final s = aw / img.width, ah = img.height * s;
    final ax = (size.width - aw) / 2, ay = size.height * 0.42 - ah / 2;
    final ly0 = ay + art.lineTop * s, ly1 = ay + art.lineBottom * s;
    final fg = Paint()..colorFilter = ColorFilter.mode(color, BlendMode.srcIn)..filterQuality = FilterQuality.high;
    final solid = Paint()..color = color;

    // Mata (proporsi sama dengan OLED: lebar 35/90, celah 20/90, pusat 11/90 di bawah garis)
    final eyeW = aw * 35 / 90, gap = aw * 20 / 90, eyeCy = ly0 + aw * 11 / 90;
    final mid = ax + aw / 2;
    if (t >= _tEyes) {
      final p = _easeInOut(_phase(t, _tEyes, _tOpen));
      final lineH = ly1 - ly0, thin = max(2.0, aw * 2 / 90);
      final open = t >= _tOpen ? _easeOutBack(_phase(t, _tOpen, _tDone - 100)) : 0.0;
      final eyeH = aw * 42 / 90;
      final h = ui.lerpDouble(lineH, thin, p)! + (eyeH - thin) * open;
      final cy = ui.lerpDouble((ly0 + ly1) / 2, eyeCy, p)!;
      final l0 = ui.lerpDouble(ax, mid - gap / 2 - eyeW, p)!, l1 = ui.lerpDouble(mid, mid - gap / 2, p)!;
      final r0 = ui.lerpDouble(mid, mid + gap / 2, p)!, r1 = ui.lerpDouble(ax + aw, mid + gap / 2 + eyeW, p)!;
      final rad = Radius.circular(min(h / 2, aw * 10 / 90 * max(open, 0.1)));
      canvas.drawRRect(RRect.fromLTRBR(l0, cy - h / 2, l1, cy + h / 2, rad), solid);
      canvas.drawRRect(RRect.fromLTRBR(r0, cy - h / 2, r1, cy + h / 2, rad), solid);
      return;
    }

    final half = aw / 2 * _easeOut(_phase(t, _tLine, _tDrop));
    final drop = _phase(t, _tDrop, _tHook);
    var down = 1.0;
    var hook = t >= _tHook ? _easeOutBack(_phase(t, _tHook, _tTag)) : 0.0;
    if (t >= _tOut) {
      final p = _easeInOut(_phase(t, _tOut, _tEyes));
      down = 1 - p;
      hook = 1 - p;
    }
    final dst = Rect.fromLTWH(ax, ay, aw, ah);
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());

    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    // Garis atas tumbuh dari tengah
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(mid - half, ly0, mid + half, ly1));
    canvas.drawImageRect(img, src, dst, fg);
    canvas.restore();
    // Badan huruf turun, gelombang kiri -> kanan
    final below = ay + ah - ly1;
    final body = Path()..moveTo(ax, ly1);
    const n = 40;
    for (var i = 0; i <= n; i++) {
      final fx = i / n;
      final d = _easeOut(((drop - 0.35 * fx) / 0.65).clamp(0.0, 1.0)) * down;
      body.lineTo(ax + aw * fx, ly1 + d * below);
    }
    body..lineTo(ax + aw, ly1)..close();
    canvas.save();
    canvas.clipPath(body);
    canvas.drawImageRect(img, src, dst, fg);
    canvas.restore();
    // Matra ो naik dari balik garis
    if (hook > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(ax - 20, 0, ax + aw + 20, ly0));
      canvas.translate(0, (1 - hook) * art.lineTop * s);
      canvas.drawImageRect(img, src, dst, fg);
      canvas.restore();
    }
    // Kilau miring (hanya di atas tulisan)
    if (t >= _tGlint && t < _tOut) {
      final p = _phase(t, _tGlint, _tGlint + 550);
      final bx = ax - aw * 0.25 + aw * 1.5 * p;
      canvas.save();
      canvas.translate(bx, ay);
      canvas.skew(-0.5, 0);
      canvas.drawRect(
        Rect.fromLTWH(0, -ah, aw * 0.08, ah * 3),
        Paint()
          ..blendMode = BlendMode.srcATop
          ..color = Colors.white.withValues(alpha: 0.85),
      );
      canvas.restore();
    }
    canvas.restore();

    // LOKANA mengetik per huruf
    if (t >= _tTag) {
      var shown = min(6, ((t - _tTag) / 70).floor() + 1);
      if (t >= _tOut) shown = max(0, 6 - ((t - _tOut) / 40).floor());
      const tag = 'LOKANA';
      final style = TextStyle(
        fontFamily: 'Baloo2',
        fontSize: aw * 0.11,
        letterSpacing: aw * 0.075,
        color: color.withValues(alpha: 0.9),
        fontVariations: const [FontVariation('wght', 600)],
      );
      final full = TextPainter(text: TextSpan(text: tag, style: style), textDirection: TextDirection.ltr)..layout();
      final tx = (size.width - full.width + style.letterSpacing!) / 2, ty = ay + ah + aw * 0.12;
      full.dispose();
      for (var i = 0; i < shown; i++) {
        final age = t - _tTag - i * 70;
        final lift = t < _tOut && age < 120 ? (1 - age / 120) * aw * 0.03 : 0.0;
        final pre = TextPainter(text: TextSpan(text: tag.substring(0, i), style: style), textDirection: TextDirection.ltr)
          ..layout();
        final ch = TextPainter(text: TextSpan(text: tag[i], style: style), textDirection: TextDirection.ltr)..layout();
        ch.paint(canvas, Offset(tx + (i == 0 ? 0 : pre.width), ty + lift));
        pre.dispose();
        ch.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(_SplashPainter old) => old.t != t || old.color != color || old.art != art;
}
