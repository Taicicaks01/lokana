import 'dart:convert';
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import '../link/link.dart';
import '../link/proto.dart';
import '../main.dart';
import '../theme.dart';
import '../ui.dart';
import '../cube.dart';
import 'cube_page.dart';
import 'guide_page.dart';

/// Pengaturan (DESIGN.md §3): kartu perangkat, Lokana (SETTINGS, perlu tersambung), Aplikasi (disimpan di HP),
/// dan Lainnya (cara pakai, pratinjau Cube, lisensi, versi).
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final link = LokanaLink.instance;
  final theme = AppTheme.instance;
  final nameCtrl = TextEditingController();
  static const timeouts = {15: '15 dtk', 30: '30 dtk', 60: '1 mnt', 300: '5 mnt', 0: 'Tidak pernah'};

  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    link.addListener(_changed);
    theme.addListener(_changed);
    nameCtrl.text = link.settings?.deviceName ?? '';
    if (link.ready) link.send(T.settings, pSettingsGet());   // segarkan; REPORT datang lewat link
  }

  @override
  void dispose() {
    link.removeListener(_changed);
    theme.removeListener(_changed);
    nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _set(Uint8ListBuilder build) async {
    await sendWithFeedback(context, T.settings, build());
  }

  String get _name => (link.settings?.deviceName.isNotEmpty ?? false)
      ? link.settings!.deviceName
      : link.info?.name ?? link.name ?? link.saved?.name ?? 'Lokana';

  /// Ganti nama Bluetooth di lembar bawah (isian + simpan).
  Future<void> _editName() async {
    nameCtrl.text = link.settings?.deviceName ?? '';
    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(builder: (c, setSheet) {
        final t = Theme.of(c).textTheme;
        final bytes = bleNameBytes(nameCtrl.text.trim()).length;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(c).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Nama Bluetooth', style: t.titleLarge),
            const SizedBox(height: Gap.xs),
            Text('Nama yang muncul saat HP mencari Lokana. Boleh huruf Dewanagari, misalnya Lokana_लोचन-01; '
                'di layar Lokana tampil sebagai huruf Latin.', style: t.bodySmall),
            const SizedBox(height: Gap.m),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setSheet(() {}),
              onSubmitted: (_) => Navigator.pop(c, true),
              decoration: InputDecoration(
                hintText: 'Lokana_लोचन-01',
                helperText: 'Kosong = nama bawaan',
                counterText: '$bytes/26 byte',
                errorText: utf8.encode(nameCtrl.text.trim()).length > 26 ? 'Terlalu panjang, akan dipotong' : null,
              ),
            ),
            const SizedBox(height: Gap.m),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)).merge(AppTheme.primaryButton(c)),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Simpan nama'),
            ),
          ]),
        );
      }),
    );
    if (save != true || !mounted) return;
    await _set(() => pSettingsSet(deviceName: nameCtrl.text.trim()));
    if (mounted) {
      showSnack(context, 'Nama berganti. HP lain mungkin menampilkan nama lama sampai Bluetooth-nya dimatikan-nyalakan.');
    }
  }

  void _open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final lk = context.lk;
    final s = link.ready ? link.settings : null;
    final info = link.info;
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: PageBody(children: [
        // ---------------- Kartu perangkat ----------------
        Material(
          color: lk.hero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LokanaTokens.rCard), side: const BorderSide(color: Colors.white10)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(children: [
              LokanaCube(scale: 0.42, mood: link.ready ? CubeMood.idle : CubeMood.mengantuk),
              const SizedBox(width: Gap.l),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_name,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(color: Colors.white)),
                  const SizedBox(height: Gap.xs),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    link.ready
                        ? Pill('Tersambung', icon: Icons.circle, color: lk.ok)
                        : const Pill('Belum tersambung', icon: Icons.circle_outlined, color: Colors.white54),
                    if (info != null) Pill('Lokana OS ${info.fwVersion}', color: AppTheme.instance.oled.color),
                  ]),
                ]),
              ),
            ]),
          ),
        ),

        // ---------------- Lokana ----------------
        const SectionHeader('Lokana', icon: Icons.remove_red_eye_outlined, subtitle: 'Disimpan di Lokana'),
        if (s == null && link.ready)
          const _Skeleton()                               // REPORT pengaturan sedang dibaca
        else if (s == null)
          const Notice('Sambungkan Lokana untuk mengubah kecerahan, suara, layar, dan nama.', icon: Icons.bluetooth_disabled)
        else
          Panel(children: [
            Field('Kecerahan layar', first: true,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Redup')),
                    ButtonSegment(value: 1, label: Text('Sedang')),
                    ButtonSegment(value: 2, label: Text('Terang')),
                  ],
                  selected: {s.brightness},
                  onSelectionChanged: (v) => _set(() => pSettingsSet(brightness: v.first)),
                )),
            Field('Layar mati otomatis',
                child: Choices<int>(
                  options: timeouts,
                  value: s.screenTimeoutS,
                  onChanged: (v) => _set(() => pSettingsSet(screenTimeoutS: v)),
                )),
            const SizedBox(height: Gap.s),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.volume_up_outlined),
              title: const Text('Suara'),
              subtitle: const Text('Bunyi tombol & efek. Cari kunci tetap berbunyi.'),
              value: s.sound,
              onChanged: (v) => _set(() => pSettingsSet(sound: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.screen_rotation_alt_outlined),
              title: const Text('Putar layar 180°'),
              subtitle: const Text('Untuk Lokana yang dipasang terbalik'),
              value: s.flip,
              onChanged: (v) => _set(() => pSettingsSet(flip: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.slideshow_outlined),
              title: const Text('Panduan setelah menyala'),
              subtitle: Text(s.bootGuide == null ? 'Perlu Lokana OS 0.5.3' : 'Peragaan gerakan sesudah animasi pembuka'),
              value: s.bootGuide ?? false,
              onChanged: s.bootGuide == null ? null : (v) => _set(() => pSettingsSet(bootGuide: v)),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bluetooth_outlined),
              title: const Text('Nama Bluetooth'),
              subtitle: Text(s.deviceName.isEmpty ? 'Nama bawaan' : s.deviceName, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: TextButton(onPressed: _editName, child: const Text('Ubah')),
              onTap: _editName,
            ),
          ]),

        // ---------------- Aplikasi ----------------
        const SectionHeader('Aplikasi', icon: Icons.palette_outlined, subtitle: 'Disimpan di HP ini'),
        Panel(children: [
          Field('Tema', first: true,
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('Sistem')),
                  ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Terang')),
                  ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Gelap')),
                ],
                selected: {theme.mode},
                onSelectionChanged: (v) => theme.setMode(v.first),
              )),
          Field('Warna aksen', help: 'Lokana Cube & ikon tetap pink.',
              child: Wrap(spacing: Gap.s, runSpacing: Gap.m, children: [
                for (final a in AppTheme.accents)
                  _ColorDot(color: a.color, label: a.label, selected: theme.accent.id == a.id, onTap: () => theme.setAccent(a)),
              ])),
          Field('Warna layar OLED', help: 'Samakan dengan warna OLED Lokana-mu. Dipakai di pratinjau & mata Lokana Cube.',
              child: Wrap(spacing: Gap.s, runSpacing: Gap.m, children: [
                for (final o in AppTheme.oledColors)
                  _ColorDot(color: o.color, label: o.label, selected: theme.oled.id == o.id, onTap: () => theme.setOled(o),
                      dark: true),
              ])),
          const SizedBox(height: Gap.s),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.auto_awesome_outlined),
            title: const Text('Animasi pembuka लोचन'),
            subtitle: const Text('Tampil saat aplikasi dibuka. Tap untuk melewati.'),
            value: theme.splash,
            onChanged: theme.setSplash,
          ),
        ]),

        // ---------------- Lainnya ----------------
        const SectionHeader('Lainnya', icon: Icons.more_horiz),
        Panel(padding: const EdgeInsets.symmetric(vertical: 6), children: [
          NavRow(icon: Icons.menu_book_outlined, title: 'Cara pakai Lokana', subtitle: 'Gerakan, modul, menu, dan tips',
              onTap: () => _open(const GuidePage())),
          NavRow(icon: Icons.smart_toy_outlined, title: 'Lokana Cube', subtitle: 'Pratinjau gambar & mood Lokana',
              onTap: () => _open(const CubePage())),
          NavRow(icon: Icons.gavel_outlined, title: 'Lisensi', subtitle: 'Kode MIT · font Baloo 2 (OFL)',
              onTap: () => showLicensePage(context: context, applicationName: 'Lokana', applicationVersion: appVersion)),
          const Divider(indent: 16, endIndent: 16),
          ListTile(
            title: const Text('Aplikasi Lokana'),
            trailing: Text(appVersion, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
          if (info != null)
            ListTile(
              title: const Text('Lokana OS'),
              trailing: Text(info.fwVersion, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ),
        ]),
      ]),
    );
  }
}

/// Kerangka abu-abu berbentuk kartu selama pengaturan dibaca (DESIGN.md §5), bukan spinner.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final lk = context.lk;
    Widget bar(double w, double h) => Container(
        width: w, height: h, decoration: BoxDecoration(color: lk.surface2, borderRadius: BorderRadius.circular(10)));
    return Panel(children: [
      Align(alignment: Alignment.centerLeft, child: bar(120, 14)),
      const SizedBox(height: Gap.s),
      bar(double.infinity, 48),
      const SizedBox(height: Gap.l),
      Align(alignment: Alignment.centerLeft, child: bar(150, 14)),
      const SizedBox(height: Gap.s),
      Row(children: [for (var i = 0; i < 3; i++) ...[bar(70, 36), const SizedBox(width: 8)]]),
      const SizedBox(height: Gap.l),
      for (var i = 0; i < 3; i++) ...[bar(double.infinity, 40), const SizedBox(height: 10)],
    ]);
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool selected, dark;
  final VoidCallback onTap;
  const _ColorDot({required this.color, required this.label, required this.selected, required this.onTap, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 64,
        child: Column(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: dark ? Colors.black : color,
              shape: BoxShape.circle,
              border: Border.all(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 3 : 1),
            ),
            child: dark
                ? Center(child: Container(width: 14, height: 14, color: color))
                : selected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall, textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

typedef Uint8ListBuilder = Uint8List Function();
