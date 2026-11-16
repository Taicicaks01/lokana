import 'dart:async';
import 'package:material_ui/material_ui.dart';
import '../link/link.dart';
import '../link/proto.dart';
import '../main.dart';
import '../theme.dart';
import '../ui.dart';
import 'guide_page.dart';
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

  String get _name => (link.settings?.deviceName.isNotEmpty ?? false)
      ? link.settings!.deviceName
      : link.info?.name ?? link.name ?? 'Lokana';

  @override
  Widget build(BuildContext context) {
    final info = link.info;
    bool can(int cap) => info == null || info.has(cap);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lokana'),
        actions: [
          IconButton(
            tooltip: 'Cara pakai',
            onPressed: () => _open(const GuidePage()),
            icon: const Icon(Icons.help_outline),
          ),
          PopupMenuButton<String>(
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
        _Hero(name: _name, info: info, onTap: can(Caps.screen) ? () => _open(const ScreenPage()) : null),
        const SizedBox(height: Gap.m),

        // ---------- Aksi cepat ----------
        Row(children: [
          Expanded(
            child: _QuickAction(
              icon: link.findingKeys ? Icons.volume_off_rounded : Icons.key_rounded,
              label: link.findingKeys ? 'Hentikan' : 'Cari kunci',
              active: link.findingKeys,
              onTap: _findKeys,
            ),
          ),
          const SizedBox(width: Gap.s),
          Expanded(
            child: _QuickAction(
              icon: Icons.schedule_rounded,
              label: 'Sinkron jam',
              onTap: () => sendWithFeedback(context, T.timeSync, pTimeSync(DateTime.now()), ok: 'Jam Lokana disinkronkan'),
            ),
          ),
          if (can(Caps.screen)) ...[
            const SizedBox(width: Gap.s),
            Expanded(
              child: _QuickAction(
                  icon: Icons.screenshot_monitor_rounded, label: 'Layar', onTap: () => _open(const ScreenPage())),
            ),
          ],
        ]),

        // ---------- Tampilkan ----------
        const SectionHeader('Tampilkan di Lokana'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: Gap.s,
          crossAxisSpacing: Gap.s,
          childAspectRatio: 1.35,
          children: [
            if (can(Caps.customText))
              FeatureCard(icon: Icons.text_fields_rounded, title: 'Teks', subtitle: 'Pesan, name tag, 5 font',
                  onTap: () => _open(const TextPage())),
            if (can(Caps.bitmap))
              FeatureCard(icon: Icons.emoji_emotions_outlined, title: 'Emoji & Gambar', subtitle: 'Emoji, foto, dan GIF',
                  onTap: () => _open(const ImagePage())),
            FeatureCard(icon: Icons.mood_rounded, title: 'Ekspresi', subtitle: 'Ubah raut wajah Lokana',
                onTap: () => _open(const ExpressionPage())),
            if (can(Caps.dice))
              FeatureCard(icon: Icons.casino_outlined, title: 'Dadu', subtitle: 'Lempar & lihat riwayat',
                  onTap: () => _open(const DicePage())),
          ],
        ),

        // ---------- HP & Lokana ----------
        const SectionHeader('HP & Lokana'),
        Panel(padding: const EdgeInsets.symmetric(vertical: 6), children: [
          if (can(Caps.notif))
            NavRow(icon: Icons.notifications_outlined, title: 'Notifikasi',
                subtitle: 'Teruskan notifikasi & panggilan', onTap: () => _open(const NotifPage())),
          if (can(Caps.findPhone))
            NavRow(icon: Icons.phonelink_ring_outlined, title: 'Cari HP',
                subtitle: 'Atur nada · di Lokana: modul Cari HP lalu tap', onTap: () => _open(const SettingsPage())),
          NavRow(icon: Icons.settings_outlined, title: 'Pengaturan',
              subtitle: 'Kecerahan, suara, nama, tema', onTap: () => _open(const SettingsPage())),
          NavRow(icon: Icons.menu_book_outlined, title: 'Cara pakai Lokana',
              subtitle: 'Gerakan, modul, dan menu', onTap: () => _open(const GuidePage())),
        ]),
      ]),
    );
  }
}

/// Kartu utama: wajah Lokana di "layar OLED", nama, dan status.
class _Hero extends StatelessWidget {
  final String name;
  final DeviceInfo? info;
  final VoidCallback? onTap;
  const _Hero({required this.name, required this.info, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final oled = AppTheme.instance.oled.color;
    final i = info;
    return Card(
      color: Colors.black,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Colors.white12)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: LokanaEyes(color: oled, height: 54)),
            const SizedBox(height: Gap.l),
            Text(name, style: t.headlineSmall?.copyWith(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: Gap.s),
            Wrap(spacing: 6, runSpacing: 6, children: [
              const Pill('Tersambung', icon: Icons.circle, color: Color(0xFF6EE7A8)),
              if (i != null) Pill('Lokana OS ${i.fwVersion}', color: oled),
              if (i != null) Pill(i.batteryText, icon: Icons.bolt_rounded, color: Colors.white70),
            ]),
            if (onTap != null) ...[
              const SizedBox(height: Gap.s),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('Lihat layar langsung', style: t.labelMedium?.copyWith(color: Colors.white60)),
                const Icon(Icons.chevron_right, size: 18, color: Colors.white60),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  const _QuickAction({required this.icon, required this.label, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: active ? cs.tertiary : cs.secondaryContainer,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(children: [
            Icon(icon, color: active ? cs.onTertiary : cs.onSecondaryContainer),
            const SizedBox(height: 6),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: active ? cs.onTertiary : cs.onSecondaryContainer)),
          ]),
        ),
      ),
    );
  }
}
