import 'package:material_ui/material_ui.dart';
import '../link/link.dart';
import '../link/proto.dart';
import '../main.dart';
import '../render.dart';

/// BITMAP: emoji atau teks bebas digambar HP menjadi gambar 1-bit, lalu dikirim ke Lokana.
class ImagePage extends StatefulWidget {
  const ImagePage({super.key});

  @override
  State<ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<ImagePage> {
  static const quick = ['😊', '😂', '😍', '😎', '🥳', '😴', '👍', '❤️', '⭐', '🔥', '☕', '🎵', '🐱', '🌙', '⚡', '🍀'];
  final ctrl = TextEditingController(text: '😊');
  Bitmap1? bmp;
  double threshold = 110;
  bool invert = false;
  int slot = 0, duration = 10;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  Future<void> _render() async {
    final text = ctrl.text.trim();
    if (text.isEmpty) { setState(() => bmp = null); return; }
    final info = LokanaLink.instance.info;
    final b = await renderToBitmap(text,
        w: info?.screenW ?? 128, h: info?.screenH ?? 64, threshold: threshold.round(), invert: invert);
    if (mounted) setState(() => bmp = b);
  }

  Future<void> _send() async {
    final b = bmp;
    if (b == null) return;
    await sendWithFeedback(
      context,
      T.bitmap,
      pBitmap(b, op: slot == 0 ? 0 : 1, slot: slot, durationS: slot == 0 ? duration : 0),
      ok: slot == 0 ? 'Terkirim' : 'Disimpan ke slot gambar $slot',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Emoji & Gambar')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        OledPreview(bitmap: bmp),
        const SizedBox(height: 16),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final e in quick)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () { ctrl.text = e; _render(); },
              child: Padding(padding: const EdgeInsets.all(6), child: Text(e, style: const TextStyle(fontSize: 28))),
            ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: ctrl,
          maxLength: 24,
          onChanged: (_) => _render(),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Emoji atau teks',
            helperText: 'Boleh emoji apa saja, huruf beraksen, atau gabungan seperti "Hai 👋"',
          ),
        ),
        const SizedBox(height: 8),
        Text('Ketajaman: ${threshold.round()}', style: t.titleSmall),
        Slider(value: threshold, min: 20, max: 235, onChanged: (v) => setState(() => threshold = v), onChangeEnd: (_) => _render()),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Balik warna'),
          value: invert,
          onChanged: (v) { setState(() => invert = v); _render(); },
        ),
        const SizedBox(height: 8),
        Text('Kirim ke', style: t.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(label: const Text('Tampilkan sekarang'), selected: slot == 0, onSelected: (_) => setState(() => slot = 0)),
          for (var s = 1; s <= 8; s++)
            ChoiceChip(label: Text('Slot $s'), selected: slot == s, onSelected: (_) => setState(() => slot = s)),
        ]),
        if (slot == 0) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final d in const [5, 10, 30, 0])
              ChoiceChip(label: Text(d == 0 ? 'Sampai disentuh' : '$d detik'), selected: duration == d,
                  onSelected: (_) => setState(() => duration = d)),
          ]),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: bmp == null ? null : _send,
          icon: Icon(slot == 0 ? Icons.send : Icons.save),
          label: Text(slot == 0 ? 'Kirim ke Lokana' : 'Simpan ke slot $slot'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        if (slot != 0)
          TextButton(
            onPressed: () => sendWithFeedback(context, T.bitmap, pBitmapDelete(slot), ok: 'Slot gambar $slot dihapus'),
            child: Text('Hapus slot $slot'),
          ),
      ]),
    );
  }
}
