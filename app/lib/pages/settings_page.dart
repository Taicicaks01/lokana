import 'dart:convert';
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import '../link/link.dart';
import '../link/proto.dart';
import '../main.dart';
import '../theme.dart';
import '../ui.dart';
import 'guide_page.dart';

/// Pengaturan: bagian Aplikasi (tema, disimpan di HP) dan bagian Lokana (SETTINGS, perlu tersambung).
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

  String? ringtone;

  void _changed() => setState(() {});

  Future<void> _pickRingtone({bool file = false}) async {
    final t = await link.pickRingtone(file: file);
    if (t != null && mounted) setState(() => ringtone = t);
  }

  @override
  void initState() {
    super.initState();
    link.addListener(_changed);
    theme.addListener(_changed);
    nameCtrl.text = link.settings?.deviceName ?? '';
    link.ringtoneTitle().then((t) => mounted ? setState(() => ringtone = t) : null);
    if (link.ready) link.send(T.settings, pSettingsGet());   // segarkan; REPORT datang lewat link
  }

  @override
  void dispose() {
    link.removeListener(_changed);
    theme.removeListener(_changed);
    link.stopRingtonePreview();
    nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _set(Uint8ListBuilder build) async {
    await sendWithFeedback(context, T.settings, build());
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final s = link.ready ? link.settings : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: PageBody(children: [
        // ---------------- Bantuan ----------------
        Card(
          color: cs.primaryContainer,
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: IconBadge(Icons.menu_book_outlined, background: cs.primary, color: cs.onPrimary),
            title: Text('Cara pakai Lokana', style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
            subtitle: Text('Gerakan, modul, menu, dan panduan di layar Lokana',
                style: TextStyle(color: cs.onPrimaryContainer)),
            trailing: Icon(Icons.chevron_right, color: cs.onPrimaryContainer),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuidePage())),
          ),
        ),

        // ---------------- Lokana ----------------
        const SectionHeader('Lokana', icon: Icons.remove_red_eye_outlined, subtitle: 'Disimpan di Lokana'),
        if (s == null)
          Notice(link.ready ? 'Membaca pengaturan Lokana...' : 'Sambungkan Lokana untuk mengubah kecerahan, suara, dan nama.',
              icon: link.ready ? Icons.hourglass_top : Icons.bluetooth_disabled)
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Suara'),
              subtitle: const Text('Bunyi tombol & efek. Cari kunci tetap berbunyi.'),
              value: s.sound,
              onChanged: (v) => _set(() => pSettingsSet(sound: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Putar layar 180°'),
              value: s.flip,
              onChanged: (v) => _set(() => pSettingsSet(flip: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Panduan setelah menyala'),
              subtitle: Text(s.bootGuide == null ? 'Perlu firmware Lokana 0.5.3' : 'Peragaan gerakan sesudah animasi pembuka'),
              value: s.bootGuide ?? false,
              onChanged: s.bootGuide == null ? null : (v) => _set(() => pSettingsSet(bootGuide: v)),
            ),
            Field('Nama Bluetooth',
                help: 'Nama yang muncul saat HP mencari Lokana. Boleh huruf Dewanagari, misalnya Lokana_लोचन-01; '
                    'di layar Lokana tampil sebagai huruf Latin.',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextField(
                      controller: nameCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Lokana_लोचन-01',
                        helperText: 'Kosong = nama bawaan',
                        counterText: '${bleNameBytes(nameCtrl.text.trim()).length}/26 byte',
                        errorText: utf8.encode(nameCtrl.text.trim()).length > 26 ? 'Terlalu panjang, akan dipotong' : null,
                      ),
                    ),
                  const SizedBox(height: Gap.s),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Simpan nama'),
                      onPressed: () async {
                        FocusScope.of(context).unfocus();
                        await _set(() => pSettingsSet(deviceName: nameCtrl.text.trim()));
                        if (context.mounted) {
                          showSnack(context, 'Nama berganti. HP lain mungkin menampilkan nama lama sampai Bluetooth-nya '
                              'dimatikan-nyalakan.');
                        }
                      },
                    ),
                  ),
                ])),
          ]),

        // ---------------- Cari HP (nada di HP ini) ----------------
        const SectionHeader('Nada Cari HP', icon: Icons.ring_volume_outlined, subtitle: 'Disimpan di HP ini'),
        Panel(children: [
          Text('Berbunyi saat modul Cari HP di Lokana ditap. Selalu keras, walau HP dalam mode senyap.', style: t.bodySmall),
          const SizedBox(height: Gap.s),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const IconBadge(Icons.music_note_outlined, size: 40),
            title: Text(ringtone ?? '...', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: const Text('Nada sekarang'),
            trailing: IconButton.filledTonal(
              tooltip: 'Coba (4 detik)',
              onPressed: link.previewRingtone,
              icon: const Icon(Icons.play_arrow),
            ),
          ),
          const SizedBox(height: Gap.xs),
          Wrap(spacing: Gap.s, runSpacing: Gap.s, children: [
            OutlinedButton.icon(
                onPressed: _pickRingtone, icon: const Icon(Icons.library_music_outlined), label: const Text('Nada HP')),
            OutlinedButton.icon(
                onPressed: () => _pickRingtone(file: true),
                icon: const Icon(Icons.audio_file_outlined),
                label: const Text('File audio')),
            TextButton(
              onPressed: () async {
                final t = await link.resetRingtone();
                if (t != null && mounted) setState(() => ringtone = t);
              },
              child: const Text('Bawaan'),
            ),
          ]),
        ]),

        // ---------------- Aplikasi ----------------
        const SectionHeader('Tampilan aplikasi', icon: Icons.palette_outlined),
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
          Field('Warna aksen',
              child: Wrap(spacing: Gap.s, runSpacing: Gap.m, children: [
                for (final a in AppTheme.accents)
                  _ColorDot(color: a.color, label: a.label, selected: theme.accent.id == a.id, onTap: () => theme.setAccent(a)),
              ])),
          Field('Warna layar di pratinjau', help: 'Samakan dengan warna OLED Lokana-mu.',
              child: Wrap(spacing: Gap.s, runSpacing: Gap.m, children: [
                for (final o in AppTheme.oledColors)
                  _ColorDot(color: o.color, label: o.label, selected: theme.oled.id == o.id, onTap: () => theme.setOled(o),
                      dark: true),
              ])),
          const SizedBox(height: Gap.s),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Animasi pembuka लोचन'),
            subtitle: const Text('Tampil saat aplikasi dibuka. Tap untuk melewati.'),
            value: theme.splash,
            onChanged: theme.setSplash,
          ),
        ]),

        // ---------------- Tentang ----------------
        const SectionHeader('Tentang', icon: Icons.info_outline),
        Panel(padding: const EdgeInsets.symmetric(vertical: 4), children: [
          ListTile(
            title: const Text('Aplikasi Lokana'),
            trailing: Text(appVersion, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
          if (link.info != null)
            ListTile(
              title: const Text('Lokana OS'),
              trailing: Text(link.info!.fwVersion, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            ),
          ListTile(
            title: const Text('Lisensi'),
            subtitle: const Text('Kode MIT · font Baloo 2 (OFL)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(context: context, applicationName: 'Lokana', applicationVersion: appVersion),
          ),
        ]),
      ]),
    );
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
