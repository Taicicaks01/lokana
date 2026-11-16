import 'dart:convert';
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import '../link/link.dart';
import '../link/proto.dart';
import '../main.dart';
import '../theme.dart';

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
  static const timeouts = {15: '15 dtk', 30: '30 dtk', 60: '1 mnt', 300: '5 mnt', 0: 'Tidak'};

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

  Widget _section(String title, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(children: [
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cs.primary)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final s = link.ready ? link.settings : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // ---------------- Aplikasi ----------------
        _section('Tampilan aplikasi', Icons.palette_outlined),
        Text('Tema', style: t.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('Sistem')),
            ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Terang')),
            ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Gelap')),
          ],
          selected: {theme.mode},
          onSelectionChanged: (v) => theme.setMode(v.first),
        ),
        const SizedBox(height: 16),
        Text('Warna aksen', style: t.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final a in AppTheme.accents)
            _ColorDot(color: a.color, label: a.label, selected: theme.accent.id == a.id, onTap: () => theme.setAccent(a)),
        ]),
        const SizedBox(height: 16),
        Text('Warna layar di pratinjau', style: t.titleSmall),
        const SizedBox(height: 4),
        Text('Samakan dengan warna OLED Lokana-mu.', style: t.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final o in AppTheme.oledColors)
            _ColorDot(color: o.color, label: o.label, selected: theme.oled.id == o.id, onTap: () => theme.setOled(o),
                dark: true),
        ]),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Animasi pembuka लोचन'),
          subtitle: const Text('Tampil saat aplikasi dibuka. Tap untuk melewati.'),
          value: theme.splash,
          onChanged: theme.setSplash,
        ),
        const SizedBox(height: 16),
        const Divider(),

        // ---------------- Lokana ----------------
        _section('Lokana', Icons.remove_red_eye_outlined),
        if (s == null)
          Card(
            color: cs.surfaceContainerHigh,
            child: ListTile(
              leading: Icon(link.ready ? Icons.hourglass_top : Icons.bluetooth_disabled),
              title: Text(link.ready ? 'Membaca pengaturan Lokana...' : 'Lokana belum tersambung'),
              subtitle: link.ready ? null : const Text('Sambungkan Lokana untuk mengubah kecerahan, suara, dan nama.'),
            ),
          )
        else ...[
          Text('Kecerahan layar', style: t.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Redup')),
              ButtonSegment(value: 1, label: Text('Sedang')),
              ButtonSegment(value: 2, label: Text('Terang')),
            ],
            selected: {s.brightness},
            onSelectionChanged: (v) => _set(() => pSettingsSet(brightness: v.first)),
          ),
          const SizedBox(height: 16),
          Text('Layar mati otomatis', style: t.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in timeouts.entries)
              ChoiceChip(label: Text(e.value), selected: s.screenTimeoutS == e.key,
                  onSelected: (_) => _set(() => pSettingsSet(screenTimeoutS: e.key))),
          ]),
          const SizedBox(height: 8),
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
          const SizedBox(height: 16),
          Text('Nama Bluetooth', style: t.titleSmall),
          const SizedBox(height: 4),
          Text('Nama yang muncul saat HP mencari Lokana. Boleh huruf Dewanagari, misalnya Lokana_लोचन-01. '
              'Di layar Lokana, huruf Dewanagari tampil sebagai huruf Latin.', style: t.bodySmall),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: TextField(
                controller: nameCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: 'Lokana_लोचन-01',
                  helperText: 'Kosong = nama bawaan',
                  counterText: '${bleNameBytes(nameCtrl.text.trim()).length}/26 byte',
                  errorText: utf8.encode(nameCtrl.text.trim()).length > 26 ? 'Terlalu panjang, akan dipotong' : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: FilledButton(
                onPressed: () async {
                  FocusScope.of(context).unfocus();
                  await _set(() => pSettingsSet(deviceName: nameCtrl.text.trim()));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Nama berganti. HP lain mungkin menampilkan nama lama sampai Bluetooth-nya dimatikan-nyalakan.')));
                  }
                },
                child: const Text('Simpan'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text('Pengaturan juga bisa diubah langsung di Lokana: triple-tap untuk membuka menu.', style: t.bodySmall),
        ],
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
