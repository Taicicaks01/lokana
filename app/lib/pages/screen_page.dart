import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import '../link/link.dart';
import '../link/proto.dart';
import '../render.dart';
import '../theme.dart';
import '../ui.dart';

/// Layar Lokana langsung di HP (SCREEN) + remote gestur + screenshot.
class ScreenPage extends StatefulWidget {
  const ScreenPage({super.key});

  @override
  State<ScreenPage> createState() => _ScreenPageState();
}

class _ScreenPageState extends State<ScreenPage> {
  final link = LokanaLink.instance;
  StreamSubscription? _sub;
  Timer? _keepAlive;
  Anim1? frame;
  bool screenOn = true;
  int fps = 0, _count = 0;
  Timer? _fpsTimer;

  @override
  void initState() {
    super.initState();
    _sub = link.frames.where((f) => f.$1 == T.screen).listen((f) {
      final r = ScreenFrame.parse(f.$2);
      if (r == null || !mounted) return;
      _count++;
      setState(() { frame = Anim1(r.bitmap.w, r.bitmap.h, [r.bitmap]); screenOn = r.screenOn; });
    });
    _start();
    _keepAlive = Timer.periodic(const Duration(seconds: 10), (_) => _start());   // mirror berhenti 30 dtk tanpa START
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() { fps = _count; _count = 0; });
    });
  }

  void _start() => link.send(T.screen, pScreenStart(10), ack: false);

  @override
  void dispose() {
    _sub?.cancel();
    _keepAlive?.cancel();
    _fpsTimer?.cancel();
    link.send(T.screen, pScreenOp(ScreenOp.stop), ack: false);
    super.dispose();
  }

  Future<void> _press(int g) => link.send(T.screen, pScreenInput(g), ack: false);

  /// Screenshot 4x (piksel tajam) sebagai PNG, disimpan ke galeri HP (Pictures/Lokana).
  Future<void> _screenshot() async {
    final b = frame?.frames.first;
    if (b == null) return;
    const k = 4;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(Rect.fromLTWH(0, 0, b.w * k.toDouble(), b.h * k.toDouble()), Paint()..color = Colors.black);
    final p = Paint()..color = AppTheme.instance.oled.color;
    for (var y = 0; y < b.h; y++) {
      for (var x = 0; x < b.w; x++) {
        if (b.get(x, y)) c.drawRect(Rect.fromLTWH(x * k.toDouble(), y * k.toDouble(), k.toDouble(), k.toDouble()), p);
      }
    }
    final img = await rec.endRecording().toImage(b.w * k, b.h * k);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (png == null) return;
    final ok = await link.saveImage(Uint8List.view(png.buffer), 'lokana_${DateTime.now().millisecondsSinceEpoch}.png');
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(ok ? 'Screenshot disimpan di Galeri (Pictures/Lokana)' : 'Gagal menyimpan')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Layar Lokana'),
        actions: [
          IconButton(onPressed: frame == null ? null : _screenshot, icon: const Icon(Icons.photo_camera_outlined),
              tooltip: 'Screenshot'),
        ],
      ),
      body: PageBody(children: [
        Stack(children: [
          OledPreview(anim: frame),
          if (frame == null)
            const Positioned.fill(
                child: Center(child: Text('Menunggu layar Lokana...', style: TextStyle(color: Colors.white54)))),
          if (frame != null && !screenOn)
            Positioned.fill(
              child: Center(
                child: Chip(avatar: const Icon(Icons.bedtime_outlined, size: 18), label: const Text('Layar Lokana mati')),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.circle, size: 10, color: fps > 0 ? Colors.green : cs.outline),
          const SizedBox(width: 6),
          Text(fps > 0 ? 'Langsung · $fps fps' : 'Diam (dikirim saat layar berubah)', style: t.bodySmall),
        ]),
        const SizedBox(height: 24),
        Text('Remote', style: t.titleMedium),
        const SizedBox(height: 4),
        Text('Sama seperti menyentuh Lokana.', style: t.bodySmall),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.4,
          children: [
            _RemoteButton(icon: Icons.touch_app_outlined, label: 'Tap', sub: 'aksi modul', onTap: () => _press(1)),
            _RemoteButton(icon: Icons.swap_horiz, label: 'Double-tap', sub: 'modul berikutnya', onTap: () => _press(2)),
            _RemoteButton(icon: Icons.menu, label: 'Triple-tap', sub: 'menu', onTap: () => _press(3)),
            _RemoteButton(icon: Icons.pan_tool_alt_outlined, label: 'Tahan', sub: 'ubah / layar mati', onTap: () => _press(4)),
          ],
        ),
      ]),
    );
  }
}

class _RemoteButton extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final VoidCallback onTap;
  const _RemoteButton({required this.icon, required this.label, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.secondaryContainer,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Icon(icon, color: cs.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(color: cs.onSecondaryContainer, fontWeight: FontWeight.w600)),
                Text(sub, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSecondaryContainer)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
