// Radar ketinggalan (DESIGN.md §4): dua cincin berdenyut di sekitar Lokana Cube kecil.
// Kecepatan & jarak cincin mengikuti RSSI asli: dekat = rapat dan tenang, jauh = lebar dan cepat.
// Tanpa sinyal (null): cincin berhenti dan meredup.
import 'package:material_ui/material_ui.dart';
import 'cube.dart';
import 'theme.dart';

class LeaveRadar extends StatefulWidget {
  /// RSSI terakhir (dBm), null = tidak ada sinyal / terputus.
  final int? rssi;
  final double size;
  const LeaveRadar({super.key, required this.rssi, this.size = 200});

  /// 0 = sangat dekat (−50 dBm), 1 = di ujung jangkauan (−90 dBm).
  static double distance(int rssi) => ((-rssi - 50) / 40).clamp(0.0, 1.0);

  @override
  State<LeaveRadar> createState() => _LeaveRadarState();
}

class _LeaveRadarState extends State<LeaveRadar> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: _period());

  Duration _period() {
    final r = widget.rssi;
    if (r == null) return const Duration(seconds: 3);
    return Duration(milliseconds: (2800 - 1600 * LeaveRadar.distance(r)).round());   // dekat 2,8 dtk, jauh 1,2 dtk
  }

  @override
  void didUpdateWidget(LeaveRadar old) {
    super.didUpdateWidget(old);
    if (old.rssi != widget.rssi) {
      final v = _c.value;
      _c.duration = _period();
      if (_c.isAnimating) _c.repeat();
      _c.value = v;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final r = widget.rssi;
    final live = r != null && !still;
    if (live && !_c.isAnimating) _c.repeat();
    if (!live && _c.isAnimating) _c.stop();
    final far = r == null ? 0.0 : LeaveRadar.distance(r);
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(alignment: Alignment.center, children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => CustomPaint(
              painter: _RadarPainter(
                t: live ? _c.value : 0.3,
                far: far,
                active: r != null,
                color: context.lk.pink,
              ),
            ),
          ),
        ),
        // Sinyal lemah: Lokana melirik-lirik mencari HP
        LokanaCube(scale: widget.size / 200 * 0.42, mood: r == null ? CubeMood.mengantuk : far > 0.7 ? CubeMood.mencari : CubeMood.idle),
      ]),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double t, far;
  final bool active;
  final Color color;
  _RadarPainter({required this.t, required this.far, required this.active, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final rMin = size.width * 0.2;
    // Jangkauan cincin: dekat = rapat di sekitar Cube, jauh = sampai tepi
    final rMax = size.width * (0.3 + 0.2 * far);
    // Garis bantu jarak (tipis, diam)
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.06);
    canvas.drawCircle(c, size.width * 0.3, guide);
    canvas.drawCircle(c, size.width * 0.5 - 1, guide);
    for (var i = 0; i < 2; i++) {
      final p = (t + i * 0.5) % 1;
      final radius = rMin + (rMax - rMin) * p;
      final alpha = active ? (1 - p) * 0.7 : 0.12;
      canvas.drawCircle(
          c,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = active ? 2.5 - p * 1.5 : 1.5
            ..color = (active ? color : Colors.white).withValues(alpha: alpha));
    }
    if (active) {
      // Cahaya lembut di tengah
      canvas.drawCircle(
          c,
          rMin * 1.1,
          Paint()
            ..color = color.withValues(alpha: 0.10 + 0.06 * (1 - far))
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, rMin * 0.5));
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.t != t || old.far != far || old.active != active || old.color != color;
}

/// Teks status untuk radar.
String radarLabel(int? rssi) {
  if (rssi == null) return 'Tidak ada sinyal';
  final d = LeaveRadar.distance(rssi);
  final w = d < 0.3 ? 'Dekat' : d < 0.65 ? 'Agak jauh' : 'Jauh';
  return '$w · ${rssi < 0 ? '−${-rssi}' : '$rssi'} dBm';
}
