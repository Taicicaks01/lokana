import 'package:material_ui/material_ui.dart';
import '../link/proto.dart';
import '../main.dart';

/// CUSTOM_TEXT: tampilkan teks sekarang atau simpan ke slot 1-8 (name tag, pesan favorit).
class TextPage extends StatefulWidget {
  const TextPage({super.key});

  @override
  State<TextPage> createState() => _TextPageState();
}

class _TextPageState extends State<TextPage> {
  final ctrl = TextEditingController();
  int style = 0, size = 0, duration = 0, slot = 0;

  static const durations = {0: 'Sampai disentuh', 5: '5 detik', 10: '10 detik', 30: '30 detik', 60: '1 menit'};

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  Future<void> _send({bool clear = false}) async {
    final text = clear ? '' : ctrl.text.trim();
    if (text.isEmpty && slot == 0) return;
    await sendWithFeedback(
      context,
      T.customText,
      pCustomText(text, style: style, size: size, durationS: duration, slot: slot),
      ok: slot == 0 ? 'Terkirim' : (clear ? 'Slot $slot dihapus' : 'Disimpan ke slot $slot'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final warn = hasUnsupportedChars(ctrl.text);
    return Scaffold(
      appBar: AppBar(title: const Text('Teks')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: ctrl,
          maxLength: 200,
          minLines: 2,
          maxLines: 5,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: 'Teks',
            hintText: 'Contoh: Halo! Aku Lokana',
            helperText: warn ? 'Emoji & huruf khusus tampil sebagai "?". Pakai menu Emoji & Gambar untuk emoji.' : null,
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: 16),
        Text('Gaya', style: t.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Diam')),
            ButtonSegment(value: 1, label: Text('Berjalan')),
            ButtonSegment(value: 2, label: Text('Berkedip')),
          ],
          selected: {style},
          onSelectionChanged: (s) => setState(() => style = s.first),
        ),
        const SizedBox(height: 16),
        Text('Ukuran huruf', style: t.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Otomatis')),
            ButtonSegment(value: 1, label: Text('Kecil')),
            ButtonSegment(value: 2, label: Text('Sedang')),
            ButtonSegment(value: 3, label: Text('Besar')),
          ],
          selected: {size},
          onSelectionChanged: (s) => setState(() => size = s.first),
        ),
        const SizedBox(height: 16),
        Text('Kirim ke', style: t.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(label: const Text('Tampilkan sekarang'), selected: slot == 0, onSelected: (_) => setState(() => slot = 0)),
          for (var s = 1; s <= 8; s++)
            ChoiceChip(label: Text('Slot $s'), selected: slot == s, onSelected: (_) => setState(() => slot = s)),
        ]),
        if (slot == 0) ...[
          const SizedBox(height: 16),
          Text('Lama tampil', style: t.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in durations.entries)
              ChoiceChip(label: Text(e.value), selected: duration == e.key,
                  onSelected: (_) => setState(() => duration = e.key)),
          ]),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Teks di slot bisa dilihat di Lokana: double-tap sampai modul Teks, lalu tap untuk '
                'berganti slot. Cocok untuk name tag.', style: t.bodySmall),
          ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: ctrl.text.trim().isEmpty ? null : _send,
          icon: Icon(slot == 0 ? Icons.send : Icons.save),
          label: Text(slot == 0 ? 'Kirim ke Lokana' : 'Simpan ke slot $slot'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        if (slot != 0)
          TextButton(onPressed: () => _send(clear: true), child: Text('Kosongkan slot $slot')),
      ]),
    );
  }
}
