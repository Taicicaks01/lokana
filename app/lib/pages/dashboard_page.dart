import 'dart:async';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import '../cube.dart';
import '../face_preview.dart';
import '../link/link.dart';
import '../link/proto.dart';
import '../main.dart';
import '../oled_text.dart';
import '../render.dart';
import '../shell.dart';
import '../theme.dart';
import '../ui.dart';
import 'guide_page.dart';
import 'screen_page.dart';

/// Beranda (DESIGN.md §3): hero Lokana Cube + status, aksi cepat, remote, dan kisi Studio.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final link = LokanaLink.instance;
  Timer? _rssiTimer;
  int? rssi;
  Map<String, Anim1>? thumbs;

  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    link.addListener(_changed);
    _studioThumbs().then((t) => mounted ? setState(() => thumbs = t) : null);
    _pollRssi();
    _rssiTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollRssi());
  }

  @override
  void dispose() {
    link.removeListener(_changed);
    _rssiTimer?.cancel();
    super.dispose();
  }

  Future<void> _pollRssi() async {
    final r = await link.rssi();
    if (mounted && r != rssi) setState(() => rssi = r);
  }

  Future<void> _findKeys() async {
    final on = !link.findingKeys;
    final ok = await sendWithFeedback(context, T.findKeys, pFindKeys(on, seconds: 30),
        ok: on ? 'Lokana berbunyi 30 detik' : 'Bunyi dihentikan');
    if (!ok || !mounted) return;
    link.setFindingKeys(on);                      // Lokana juga melapor saat bunyi berhenti
  }

  Future<void> _syncClock() => sendWithFeedback(context, T.timeSync, pTimeSync(DateTime.now()), ok: 'Jam Lokana disinkronkan');

  Future<void> _remote(int gesture) async {
    HapticFeedback.selectionClick();
    await link.send(T.screen, pScreenInput(gesture), ack: false);
  }

  Future<void> _forget() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Lupakan Lokana ini?'),
        content: const Text('Pairing dihapus di HP dan di Lokana. Untuk menyambung lagi, pilih Lokana dari '
            'daftar dan masukkan kode 6 digit baru yang tampil di layarnya.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Lupakan')),
        ],
      ),
    );
    if (yes != true) return;
    final ok = await link.forget();
    if (!ok && mounted) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Hampir selesai'),
          content: const Text('Pairing di HP belum bisa dihapus otomatis. Hapus Lokana di Pengaturan Bluetooth '
              'HP supaya kode baru diminta saat menyambung lagi.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Nanti')),
            FilledButton(
                onPressed: () { Navigator.pop(c); link.openBluetoothSettings(); },
                child: const Text('Buka Pengaturan')),
          ],
        ),
      );
    }
  }

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  void _studio(int seg) => ShellNav.maybeOf(context)?.go(Tabs.studio, segment: seg);

  String get _name => (link.settings?.deviceName.isNotEmpty ?? false)
      ? link.settings!.deviceName
      : link.info?.name ?? link.name ?? 'Lokana';

  Widget _thumb(String key) {
    final a = thumbs?[key];
    return a == null
        ? DecoratedBox(decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)))
        : OledPreview(anim: a);
  }

  @override
  Widget build(BuildContext context) {
    final info = link.info;
    bool can(int cap) => info == null || info.has(cap);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Beranda'),
        actions: [
          IconButton(
            tooltip: 'Cara pakai',
            onPressed: () => _open(const GuidePage()),
            icon: const Icon(Icons.help_outline),
          ),
          PopupMenuButton<String>(
            tooltip: 'Lainnya',
            onSelected: (v) {
              if (v == 'off') link.disconnect();
              if (v == 'forget') _forget();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'off', child: ListTile(leading: Icon(Icons.link_off), title: Text('Putuskan'))),
              PopupMenuItem(
                  value: 'forget', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Lupakan Lokana ini'))),
            ],
          ),
        ],
      ),
      body: PageBody(children: [
        _Hero(
          name: _name,
          info: info,
          rssi: rssi,
          mood: CubeMood.idle,
          onTap: can(Caps.screen) ? () => _open(const ScreenPage()) : null,
        ),
        const SizedBox(height: Gap.m),

        // ---------- Aksi cepat ----------
        Row(children: [
          Expanded(
            child: QuickAction(
              icon: link.findingKeys ? Icons.volume_off_rounded : Icons.key_rounded,
              label: link.findingKeys ? 'Hentikan' : 'Cari kunci',
              primary: true,
              active: link.findingKeys,
              onTap: _findKeys,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: QuickAction(icon: Icons.schedule_rounded, label: 'Sinkron jam', onTap: _syncClock)),
          if (can(Caps.screen)) ...[
            const SizedBox(width: 10),
            Expanded(
              child: QuickAction(
                  icon: Icons.screenshot_monitor_rounded, label: 'Layar', onTap: () => _open(const ScreenPage())),
            ),
          ],
        ]),

        // ---------- Remote ----------
        if (can(Caps.screen)) ...[
          const SectionHeader('Remote', subtitle: 'Sama seperti menyentuh Lokana'),
          Row(children: [
            Expanded(child: _RemoteButton(icon: Icons.touch_app_outlined, label: 'Tap', onTap: () => _remote(Gestures.tap))),
            const SizedBox(width: 10),
            Expanded(
                child: _RemoteButton(icon: Icons.swipe_right_alt_rounded, label: '2× Tap', onTap: () => _remote(Gestures.double))),
            const SizedBox(width: 10),
            Expanded(
                child: _RemoteButton(icon: Icons.back_hand_outlined, label: 'Tahan', onTap: () => _remote(Gestures.hold))),
          ]),
        ],

        // ---------- Studio ----------
        const SectionHeader('Studio', subtitle: 'Buat lalu tampilkan di layar Lokana'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.16,
          children: [
            if (can(Caps.customText))
              StudioTile(thumb: _thumb('teks'), icon: Icons.text_fields_rounded, title: 'Teks',
                  subtitle: 'Pesan & name tag', onTap: () => _studio(StudioSeg.teks)),
            if (can(Caps.bitmap))
              StudioTile(thumb: _thumb('gambar'), icon: Icons.image_outlined, title: 'Gambar',
                  subtitle: 'Emoji, foto, GIF', onTap: () => _studio(StudioSeg.gambar)),
            StudioTile(thumb: _thumb('ekspresi'), icon: Icons.mood_rounded, title: 'Ekspresi',
                subtitle: 'Raut wajah Lokana', onTap: () => _studio(StudioSeg.ekspresi)),
            if (can(Caps.dice))
              StudioTile(thumb: _thumb('dadu'), icon: Icons.casino_outlined, title: 'Dadu',
                  subtitle: 'Lempar dari HP', onTap: () => _studio(StudioSeg.dadu)),
          ],
        ),
      ]),
    );
  }
}

/// Kartu utama (tetap gelap di mode terang): Lokana Cube, nama, dan status asli.
class _Hero extends StatelessWidget {
  final String name;
  final DeviceInfo? info;
  final int? rssi;
  final CubeMood mood;
  final VoidCallback? onTap;
  const _Hero({required this.name, required this.info, required this.rssi, required this.mood, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final lk = context.lk;
    final oled = AppTheme.instance.oled.color;
    final i = info;
    final r = rssi;
    return Material(
      color: lk.hero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LokanaTokens.rHero), side: const BorderSide(color: Colors.white10)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(children: [
            LokanaCube(scale: 0.82, mood: mood),
            const SizedBox(height: Gap.m),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: t.titleLarge?.copyWith(color: Colors.white)),
            const SizedBox(height: Gap.s),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
              Pill('Tersambung', icon: Icons.circle, color: lk.ok),
              if (r != null)
                Pill(r >= -60 ? 'Sinyal kuat' : r >= -75 ? 'Sinyal sedang' : 'Sinyal lemah',
                    icon: r >= -60
                        ? Icons.signal_cellular_alt_rounded
                        : r >= -75 ? Icons.signal_cellular_alt_2_bar_rounded : Icons.signal_cellular_alt_1_bar_rounded,
                    color: Colors.white70),
              // Baterai hanya jika firmware mengirim persen asli (DESIGN.md §1.5); 255 = tidak diketahui
              ?batteryPill(i),
              if (i != null) Pill('Lokana OS ${i.fwVersion}', color: oled),
            ]),
            if (onTap != null) ...[
              const SizedBox(height: Gap.m),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.touch_app_outlined, size: 16, color: Colors.white54),
                const SizedBox(width: 4),
                Text('Ketuk untuk melihat layar langsung', style: t.labelMedium?.copyWith(color: Colors.white54)),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

class _RemoteButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _RemoteButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final lk = context.lk;
    return Material(
      color: lk.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: lk.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------- Thumbnail Studio ----------------
// Dirender sekali dengan renderer yang sama dengan pratinjau (bukan ikon), dalam ukuran layar asli 128×64.
Future<Map<String, Anim1>>? _thumbCache;

Future<Map<String, Anim1>> _studioThumbs() => _thumbCache ??= () async {
      Anim1 one(Bitmap1 b) => Anim1(128, 64, [b]);
      final face = await expressionFace(1);          // senang, sama persis dengan wajah Lokana
      return {
        'teks': one(OledTextLayout('Halo!', font: 2).draw(0)),
        'gambar': one(_heart()),
        'ekspresi': one(face),
        'dadu': one(_dieFive()),
      };
    }();

Bitmap1 _heart() {
  final b = Bitmap1(128, 64);
  for (var y = 0; y < 64; y++) {
    for (var x = 0; x < 128; x++) {
      final u = (x - 64) / 24.0, v = -(y - 34) / 24.0;
      final a = u * u + v * v - 1;
      if (a * a * a - u * u * v * v * v <= 0) b.set(x, y, true);
    }
  }
  return b;
}

Bitmap1 _dieFive() {
  final b = Bitmap1(128, 64);
  const x0 = 41, y0 = 9, s = 46, r = 8, th = 3;
  bool inRounded(int x, int y, int l, int t, int size, int rad) {
    if (x < l || y < t || x >= l + size || y >= t + size) return false;
    final cx = x < l + rad ? l + rad : (x >= l + size - rad ? l + size - rad - 1 : x);
    final cy = y < t + rad ? t + rad : (y >= t + size - rad ? t + size - rad - 1 : y);
    return (x - cx) * (x - cx) + (y - cy) * (y - cy) <= rad * rad;
  }
  for (var y = 0; y < 64; y++) {
    for (var x = 0; x < 128; x++) {
      if (inRounded(x, y, x0, y0, s, r) && !inRounded(x, y, x0 + th, y0 + th, s - 2 * th, r - th)) b.set(x, y, true);
    }
  }
  const pips = [(64, 32), (52, 20), (76, 20), (52, 44), (76, 44)];
  for (final (px, py) in pips) {
    for (var y = py - 4; y <= py + 4; y++) {
      for (var x = px - 4; x <= px + 4; x++) {
        if ((x - px) * (x - px) + (y - py) * (y - py) <= 17) b.set(x, y, true);
      }
    }
  }
  return b;
}
