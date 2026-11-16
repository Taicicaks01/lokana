import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import '../link/link.dart';
import '../link/proto.dart';
import '../main.dart';

/// SETTINGS: nilai dibaca dari REPORT Lokana; setiap perubahan langsung dikirim.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final link = LokanaLink.instance;
  final nameCtrl = TextEditingController();
  static const timeouts = {15: '15 dtk', 30: '30 dtk', 60: '1 mnt', 300: '5 mnt', 0: 'Tidak'};

  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    link.addListener(_changed);
    nameCtrl.text = link.settings?.deviceName ?? '';
    link.send(T.settings, pSettingsGet());       // segarkan; REPORT datang lewat link
  }

  @override
  void dispose() {
    link.removeListener(_changed);
    nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _set(Uint8ListBuilder build) async {
    await sendWithFeedback(context, T.settings, build());
  }

  @override
  Widget build(BuildContext context) {
    final s = link.settings;
    final t = Theme.of(context).textTheme;
    if (s == null) {
      return Scaffold(appBar: AppBar(title: const Text('Pengaturan')),
          body: const Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
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
        Text('Nama Lokana', style: t.titleSmall),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: nameCtrl,
              maxLength: 24,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: link.name ?? 'Lokana',
                helperText: 'Kosong = nama bawaan',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: FilledButton(
              onPressed: () async {
                FocusScope.of(context).unfocus();
                await _set(() => pSettingsSet(deviceName: nameCtrl.text.trim()));
              },
              child: const Text('Simpan'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text('Pengaturan juga bisa diubah langsung di Lokana: triple-tap untuk membuka menu.', style: t.bodySmall),
      ]),
    );
  }
}

typedef Uint8ListBuilder = Uint8List Function();
