// Lokana Cube: gambar perangkat yang "hidup" (docs/DESIGN.md §1.1, §4). Gantungan, badan PETG pink,
// jendela OLED gelap, dan dua mata yang ikut mood. Digambar CustomPainter, tanpa paket tambahan.
//
// Proporsi mengikuti casing Lokana Cube v1 (badan 35 × 31,3 mm, jendela 25 × 13,6 mm) dan gaya ikon
// brand/ (lug di atas, sudut membulat, mata putih membulat).
import 'dart:math';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'theme.dart';

enum CubeMood {
  /// Terhubung: mata terbuka, berkedip acak tiap 3–6 detik.
  idle,
  /// Mencari Lokana: melirik kiri-kanan.
  mencari,
  /// Terputus / menyambung ulang: mata hampir terpejam.
  mengantuk,
  /// Perintah berhasil (ACK): mata melengkung senang, badan memantul kecil.
  senang,
}

// ---------- Geometri (mm) ----------
const double _bodyW = 35, _bodyH = 31.3, _bodyR = 7.6;
const double _winW = 25, _winH = 13.6, _winR = 3.0, _winTop = 4.4;
const double _lugW = 7.6, _lugH = 7.6, _lugR = 2.7, _lugHole = 1.4, _lugAbove = 5.4;
const double _totalH = _lugAbove + _bodyH;
// Mata relatif terhadap jendela (dari ikon brand: 118×170 di jendela 500×280, jarak 80)
const double _eyeW = 0.236, _eyeH = 0.607, _eyeGap = 0.16, _eyeR = 0.39;

class LokanaCube extends StatefulWidget {
  /// 1 = lebar 140 dp (4 dp per mm).
  final double scale;
  /// Warna mata (warna OLED pilihan pengguna). null = `AppTheme.oled`.
  final Color? eyeColor;
  final CubeMood mood;
  const LokanaCube({super.key, this.scale = 1, this.eyeColor, this.mood = CubeMood.idle});

  static const double dpPerMm = 4;
  static Size sizeFor(double scale) => Size(_bodyW * dpPerMm * scale, _totalH * dpPerMm * scale);

  @override
  State<LokanaCube> createState() => _LokanaCubeState();
}

class _LokanaCubeState extends State<LokanaCube> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _clock = ValueNotifier<double>(0);      // ms sejak widget dibuat
  final _rnd = Random();
  double _nextBlink = 0, _blinkAt = -1000;
  CubeMood _prev = CubeMood.idle;
  double _changedAt = -1000;

  @override
  void initState() {
    super.initState();
    _prev = widget.mood;
    _nextBlink = 1500 + _rnd.nextDouble() * 2500;
    _ticker.start();
  }

  @override
  void didUpdateWidget(LokanaCube old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) {
      _prev = old.mood;
      _changedAt = _clock.value;
    }
  }

  void _tick(Duration d) {
    final t = d.inMicroseconds / 1000.0;
    if (t >= _nextBlink) {
      _blinkAt = t;
      _nextBlink = t + 3000 + _rnd.nextDouble() * 3000;   // 3–6 dtk, tidak serempak dengan detik jam
    }
    _clock.value = t;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final size = LokanaCube.sizeFor(widget.scale);
    return Semantics(
      label: switch (widget.mood) {
        CubeMood.idle => 'Lokana',
        CubeMood.mencari => 'Lokana sedang mencari',
        CubeMood.mengantuk => 'Lokana mengantuk',
        CubeMood.senang => 'Lokana senang',
      },
      child: SizedBox.fromSize(
        size: size,
        child: CustomPaint(
          painter: _CubePainter(
            clock: _clock,
            state: this,
            still: still,
            eye: widget.eyeColor ?? AppTheme.instance.oled.color,
          ),
        ),
      ),
    );
  }
}

/// Keadaan mata pada satu waktu.
class _Eyes {
  final double open, look, happy, bounce;
  const _Eyes(this.open, this.look, this.happy, this.bounce);
  static _Eyes lerp(_Eyes a, _Eyes b, double k) => _Eyes(
      a.open + (b.open - a.open) * k, a.look + (b.look - a.look) * k,
      a.happy + (b.happy - a.happy) * k, a.bounce + (b.bounce - a.bounce) * k);
}

_Eyes _moodEyes(CubeMood m, double t, bool still) {
  if (still) {
    return switch (m) {
      CubeMood.idle => const _Eyes(1, 0, 0, 0),
      CubeMood.mencari => const _Eyes(0.9, 0.6, 0, 0),
      CubeMood.mengantuk => const _Eyes(0.18, 0, 0, 0),
      CubeMood.senang => const _Eyes(0.55, 0, 1, 0),
    };
  }
  switch (m) {
    case CubeMood.idle:
      return const _Eyes(1, 0, 0, 0);
    case CubeMood.mencari:
      // lirik kiri, diam, lirik kanan, diam (sinus yang "dipotong" supaya ada jeda di ujung)
      final look = (sin(2 * pi * t / 3200) * 1.7).clamp(-1.0, 1.0);
      return _Eyes(0.88, look, 0, 0);
    case CubeMood.mengantuk:
      final droop = 0.5 + 0.5 * sin(2 * pi * t / 3600);
      return _Eyes(0.12 + 0.1 * droop, 0, 0, 0);
    case CubeMood.senang:
      return _Eyes(0.55, 0, 1, sin(pi * ((t / 650) % 1)));  // mata lebar-pendek "∩" + pantulan kecil berulang
  }
}

class _CubePainter extends CustomPainter {
  final ValueNotifier<double> clock;
  final _LokanaCubeState state;
  final bool still;
  final Color eye;
  _CubePainter({required this.clock, required this.state, required this.still, required this.eye}) : super(repaint: clock);

  static const _screen = Color(0xFF121218);

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final s = size.width / _bodyW;                 // dp per mm
    final m = state.widget.mood;

    // Mata: transisi halus antar-mood (220 ms) + kedip
    final k = Curves.easeOutCubic.transform(((t - state._changedAt) / 220).clamp(0.0, 1.0));
    var e = _Eyes.lerp(_moodEyes(state._prev, t, still), _moodEyes(m, t, still), k);
    if (!still && (m == CubeMood.idle || m == CubeMood.mencari)) {
      final p = (t - state._blinkAt) / 160;
      if (p >= 0 && p <= 1) e = _Eyes(e.open * max(0.08, 1 - sin(pi * p)), e.look, e.happy, e.bounce);
    }

    canvas.save();
    canvas.translate(0, -e.bounce * 1.2 * s);

    // Bayangan lembut di bawah badan
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.2 * s);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(size.width / 2, (_totalH - 0.6) * s + e.bounce * 1.2 * s),
            width: _bodyW * 0.8 * s * (1 - e.bounce * 0.08), height: 2.2 * s),
        shadow);

    // Gantungan (di belakang badan), lubang tembus
    final lug = RRect.fromRectAndRadius(
        Rect.fromLTWH((_bodyW - _lugW) / 2 * s, 0, _lugW * s, _lugH * s), Radius.circular(_lugR * s));
    final lugPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(lug)
      ..addOval(Rect.fromCircle(center: Offset(_bodyW / 2 * s, _lugH * 0.44 * s), radius: _lugHole * s));
    canvas.drawPath(lugPath, Paint()..color = const Color(0xFFE76A9E));

    // Badan PETG pink: gradasi tipis + kilau tepi
    final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, _lugAbove * s, _bodyW * s, _bodyH * s), Radius.circular(_bodyR * s));
    canvas.drawRRect(
        body,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF994BE), LokanaTokens.brandPink, Color(0xFFE5649A)],
            stops: [0, 0.45, 1],
          ).createShader(body.outerRect));
    canvas.drawRRect(
        body.deflate(0.45 * s),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6 * s
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white.withValues(alpha: 0.45), Colors.white.withValues(alpha: 0.0)],
          ).createShader(body.outerRect));

    // Jendela OLED
    final win = RRect.fromRectAndRadius(
        Rect.fromLTWH((_bodyW - _winW) / 2 * s, (_lugAbove + _winTop) * s, _winW * s, _winH * s),
        Radius.circular(_winR * s));
    canvas.drawRRect(win.inflate(0.5 * s), Paint()..color = const Color(0xFFD95A8F));   // bibir jendela
    canvas.drawRRect(win, Paint()..color = _screen);
    canvas.save();
    canvas.clipRRect(win);
    paintLokanaEyes(canvas, win.outerRect, eye, open: e.open, look: e.look, happy: e.happy, bg: _screen);
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(_CubePainter old) => old.eye != eye || old.still != still || old.state != state;
}

/// Gambar dua mata Lokana di [r] (jendela OLED). Dipakai Lokana Cube; bisa juga untuk pratinjau ekspresi.
/// [open] 0..1, [look] −1 (kiri) .. 1 (kanan), [happy] 0..1 (mata melengkung), [bg] warna layar untuk potongan.
void paintLokanaEyes(Canvas canvas, Rect r, Color color,
    {double open = 1, double look = 0, double happy = 0, Color bg = const Color(0xFF121218)}) {
  final ew = r.width * _eyeW, ehFull = r.height * _eyeH, gap = r.width * _eyeGap;
  final cx = r.center.dx + look * r.width * 0.09, cy = r.center.dy - happy * r.height * 0.06;   // senang: mata sedikit naik
  final eh = max(ehFull * 0.06, ehFull * open);
  final glow = Paint()
    ..color = color.withValues(alpha: 0.35)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, ew * 0.12);
  final fill = Paint()..color = color;
  for (final dir in const [-1, 1]) {
    final x = cx + dir * (gap / 2 + ew / 2);
    final rect = Rect.fromCenter(center: Offset(x, cy), width: ew, height: eh);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(min(ew * _eyeR, eh / 2)));
    var path = Path()..addRRect(rr);
    if (happy > 0.01) {
      // potongan oval dari bawah -> lengkungan "∩" (mata tersenyum), sisa pita ±1/3 tinggi mata
      final cut = Rect.fromCenter(
          center: Offset(x, rect.bottom + eh * (0.66 - 0.77 * happy)), width: ew * 0.56, height: eh * 1.1);
      path = Path.combine(PathOperation.difference, path, Path()..addOval(cut));
    }
    canvas.drawPath(path, glow);
    canvas.drawPath(path, fill);
  }
}
