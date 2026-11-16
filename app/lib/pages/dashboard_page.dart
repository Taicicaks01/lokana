import 'dart:async';
import 'package:material_ui/material_ui.dart';
import '../link/link.dart';
import '../link/proto.dart';
import '../main.dart';
import 'dice_page.dart';
import 'expression_page.dart';
import 'image_page.dart';
import 'notif_page.dart';
import 'screen_page.dart';
import 'settings_page.dart';
import 'text_page.dart';

/// Tersambung: ringkasan Lokana + semua fitur.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final link = LokanaLink.instance;

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

  Future<void> _findKeys() async {
    final on = !link.findingKeys;
    final ok = await sendWithFeedback(context, T.findKeys, pFindKeys(on, seconds: 30),
        ok: on ? 'Lokana berbunyi 30 detik' : 'Bunyi dihentikan');
    if (!ok || !mounted) return;
    link.setFindingKeys(on);                      // Lokana juga melapor saat bunyi berhenti
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

  @override
  Widget build(BuildContext context) {
    final info = link.info;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    bool can(int cap) => info == null || info.has(cap);

    return Scaffold(
      appBar: AppBar(
        title: Text((link.settings?.deviceName.isNotEmpty ?? false)
            ? link.settings!.deviceName
            : info?.name ?? link.name ?? 'Lokana'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'sync') sendWithFeedback(context, T.timeSync, pTimeSync(DateTime.now()), ok: 'Jam disinkronkan');
              if (v == 'off') link.disconnect();
              if (v == 'forget') _forget();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'sync', child: Text('Sinkronkan jam')),
              PopupMenuItem(value: 'off', child: Text('Putuskan')),
              PopupMenuItem(value: 'forget', child: Text('Lupakan Lokana ini')),
            ],
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          color: cs.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(Icons.remove_red_eye, size: 40, color: cs.onPrimaryContainer),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Tersambung', style: t.titleMedium?.copyWith(color: cs.onPrimaryContainer)),
                  Text(
                    info == null
                        ? 'Membaca info Lokana...'
                        : 'Lokana OS ${info.fwVersion} · daya ${info.batteryText} · ${info.screenW}x${info.screenH}',
                    style: t.bodySmall?.copyWith(color: cs.onPrimaryContainer),
                  ),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.4,
          children: [
            if (can(Caps.screen))
              _Tile(icon: Icons.screenshot_monitor_outlined, label: 'Layar Lokana', onTap: () => _open(const ScreenPage())),
            if (can(Caps.notif))
              _Tile(icon: Icons.notifications_outlined, label: 'Notifikasi', onTap: () => _open(const NotifPage())),
            _Tile(icon: Icons.mood, label: 'Ekspresi', onTap: () => _open(const ExpressionPage())),
            if (can(Caps.customText))
              _Tile(icon: Icons.text_fields, label: 'Teks', onTap: () => _open(const TextPage())),
            if (can(Caps.bitmap))
              _Tile(icon: Icons.emoji_emotions_outlined, label: 'Emoji & Gambar', onTap: () => _open(const ImagePage())),
            if (can(Caps.dice)) _Tile(icon: Icons.casino_outlined, label: 'Dadu', onTap: () => _open(const DicePage())),
            _Tile(
              icon: link.findingKeys ? Icons.volume_off : Icons.key,
              label: link.findingKeys ? 'Hentikan bunyi' : 'Cari kunci',
              highlight: link.findingKeys,
              onTap: _findKeys,
            ),
            _Tile(icon: Icons.settings_outlined, label: 'Pengaturan', onTap: () => _open(const SettingsPage())),
          ],
        ),
        const SizedBox(height: 16),
        if (can(Caps.findPhone))
          Text('Cari HP: di Lokana, triple-tap untuk membuka menu, lalu tahan di "Cari HP". HP ini akan berbunyi '
              'walau dalam mode senyap.', style: t.bodySmall),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlight;
  const _Tile({required this.icon, required this.label, required this.onTap, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: highlight ? cs.tertiaryContainer : cs.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 36, color: highlight ? cs.onTertiaryContainer : cs.primary),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
