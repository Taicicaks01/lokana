import 'package:material_ui/material_ui.dart';
import '../cube.dart';
import '../link/link.dart';
import '../theme.dart';
import '../ui.dart';
import 'guide_page.dart';
import 'settings_page.dart';

/// Belum tersambung: scan Lokana di sekitar, sambungkan, pairing (kode 6 digit di OLED).
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final link = LokanaLink.instance;
  String? error;

  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    link.addListener(_changed);
  }

  @override
  void dispose() {
    link.removeListener(_changed);
    super.dispose();
  }

  Future<bool> _perms() async {
    if (await link.permissions()) return true;
    setState(() => error = 'Izin Bluetooth dibutuhkan untuk mencari Lokana.');
    return false;
  }

  Future<void> _scan() async {
    setState(() => error = null);
    if (!await _perms()) return;
    final e = await link.startScan();
    if (mounted) setState(() => error = e);
  }

  Future<void> _connect(String address, String name) async {
    setState(() => error = null);
    if (!await _perms()) return;
    final e = await link.connect(address, name);
    if (mounted) setState(() => error = e);
  }

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final lk = context.lk;
    final st = link.state;
    final busy = st == LinkState.connecting || st == LinkState.pairing || st == LinkState.reconnecting;
    final scanning = st == LinkState.scanning;
    final saved = link.saved;
    final devices = link.found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
    final who = link.name ?? saved?.name ?? 'Lokana';

    // Ekspresi & kata-kata hero mengikuti status (DESIGN.md §1.1)
    final (mood, title, sub) = switch (st) {
      LinkState.scanning => (CubeMood.mencari, 'Mencari Lokana...', 'Dekatkan Lokana yang menyala ke HP ini.'),
      LinkState.connecting => (CubeMood.idle, 'Menyambung ke $who', link.message ?? 'Sebentar ya...'),
      LinkState.pairing => (CubeMood.idle, 'Ketik kode dari layar Lokana',
          link.message ?? 'Kode 6 digit tampil di layar Lokana. Ketik di dialog pairing HP.'),
      LinkState.reconnecting => (CubeMood.mengantuk, 'Menyambung ulang...',
          link.message ?? 'Lokana akan tersambung sendiri begitu dalam jangkauan.'),
      _ => (CubeMood.mengantuk, 'Sambungkan Lokana',
          'Nyalakan Lokana dan dekatkan ke HP. Saat pertama kali, masukkan kode 6 digit yang tampil di layar Lokana.'),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Lokana'), actions: [
        IconButton(
            icon: const Icon(Icons.help_outline), tooltip: 'Cara pakai', onPressed: () => _open(const GuidePage())),
        IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Pengaturan',
            onPressed: () => _open(const SettingsPage())),
      ]),
      body: PageBody(children: [
        // ---------- Hero ----------
        Container(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
          decoration: BoxDecoration(
            color: lk.hero,
            borderRadius: BorderRadius.circular(LokanaTokens.rHero),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(children: [
            LokanaCube(scale: 0.8, mood: mood),
            const SizedBox(height: Gap.l),
            Text(title, textAlign: TextAlign.center, style: t.headlineSmall?.copyWith(color: Colors.white)),
            const SizedBox(height: Gap.xs),
            Text(sub, textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: Colors.white70)),
            const SizedBox(height: Gap.l),
            if (busy)
              TextButton(
                onPressed: () => link.disconnect(),
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                child: const Text('Batal'),
              )
            else if (saved != null) ...[
              // Aksi utama: sambung ke Lokana terakhir
              FilledButton.icon(
                onPressed: () => _connect(saved.address, saved.name),
                icon: const Icon(Icons.bluetooth_connected),
                label: Text('Sambungkan ke ${saved.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)).merge(AppTheme.primaryButton(context)),
              ),
              TextButton(
                onPressed: () => link.disconnect(forget: true),
                style: TextButton.styleFrom(foregroundColor: Colors.white60),
                child: const Text('Pakai Lokana lain'),
              ),
            ] else if (!scanning)
              FilledButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.search),
                label: const Text('Cari Lokana'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)).merge(AppTheme.primaryButton(context)),
              ),
          ]),
        ),

        if (link.action == 'bt_settings' && !busy) ...[
          const SizedBox(height: Gap.m),
          Panel(color: cs.errorContainer, children: [
            Text('Pairing lama perlu dihapus', style: t.titleSmall?.copyWith(color: cs.onErrorContainer)),
            const SizedBox(height: 4),
            Text(link.message ?? 'Lokana sudah melupakan HP ini. Hapus Lokana di Pengaturan Bluetooth HP, '
                'lalu sambungkan lagi untuk memasukkan kode baru.', style: TextStyle(color: cs.onErrorContainer)),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: link.openBluetoothSettings,
              icon: const Icon(Icons.bluetooth),
              label: const Text('Buka Pengaturan Bluetooth'),
            ),
          ]),
        ],
        if (error != null) ...[
          const SizedBox(height: Gap.m),
          Notice(error!, icon: Icons.error_outline, warning: true),
        ],

        // ---------- Lokana di sekitar ----------
        SectionHeader(
          'Lokana di sekitar',
          icon: Icons.bluetooth_searching,
          trailing: scanning
              ? TextButton.icon(onPressed: link.stopScan, icon: const Icon(Icons.stop), label: const Text('Berhenti'))
              : FilledButton.tonalIcon(
                  onPressed: busy ? null : _scan, icon: const Icon(Icons.search), label: const Text('Cari')),
        ),
        if (devices.isEmpty && scanning)
          for (var i = 0; i < 2; i++) ...[const _DeviceSkeleton(), const SizedBox(height: 10)]
        else if (devices.isEmpty)
          Panel(children: [
            Icon(Icons.radar, size: 36, color: lk.muted),
            const SizedBox(height: Gap.s),
            Text('Tekan "Cari" untuk menemukan Lokana yang menyala di dekatmu.',
                style: t.bodyMedium?.copyWith(color: lk.muted), textAlign: TextAlign.center),
          ])
        else
          for (final d in devices) ...[
            _DeviceCard(
              name: d.name,
              rssi: d.rssi,
              known: d.address == saved?.address,
              onTap: busy ? null : () => _connect(d.address, d.name),
            ),
            const SizedBox(height: 10),
          ],
      ]),
    );
  }
}

/// Kartu perangkat di daftar: Lokana Cube kecil, nama, sinyal.
class _DeviceCard extends StatelessWidget {
  final String name;
  final int rssi;
  final bool known;
  final VoidCallback? onTap;
  const _DeviceCard({required this.name, required this.rssi, required this.known, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final lk = context.lk;
    final bars = rssi >= -60 ? 3 : rssi >= -75 ? 2 : 1;
    final word = ['', 'lemah', 'sedang', 'kuat'][bars];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: lk.hero, borderRadius: BorderRadius.circular(LokanaTokens.rIcon)),
              child: const LokanaCube(scale: 0.3),
            ),
            const SizedBox(width: Gap.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Row(children: [
                  _Bars(bars: bars),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('Sinyal $word${known ? ' · Lokana-mu' : ''}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                  ),
                ]),
              ]),
            ),
            Icon(Icons.chevron_right, color: lk.muted),
          ]),
        ),
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  final int bars;
  const _Bars({required this.bars});

  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.primary, off = context.lk.line;
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (var i = 1; i <= 3; i++) ...[
        Container(
          width: 4,
          height: 4.0 + i * 3,
          decoration: BoxDecoration(color: i <= bars ? on : off, borderRadius: BorderRadius.circular(1)),
        ),
        if (i < 3) const SizedBox(width: 2),
      ],
    ]);
  }
}

/// Kerangka kartu perangkat selama mencari (DESIGN.md §5).
class _DeviceSkeleton extends StatelessWidget {
  const _DeviceSkeleton();

  @override
  Widget build(BuildContext context) {
    final lk = context.lk;
    Widget bar(double w, double h) =>
        Container(width: w, height: h, decoration: BoxDecoration(color: lk.surface2, borderRadius: BorderRadius.circular(8)));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: lk.surface2, borderRadius: BorderRadius.circular(LokanaTokens.rIcon))),
          const SizedBox(width: Gap.m),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [bar(140, 14), const SizedBox(height: 8), bar(90, 10)]),
        ]),
      ),
    );
  }
}
