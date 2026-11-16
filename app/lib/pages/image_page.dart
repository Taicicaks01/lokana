import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import '../link/link.dart';
import '../link/proto.dart';
import '../render.dart';

/// Emoji, teks, gambar & GIF -> animasi 1-bit; kirim sekarang atau simpan ke galeri Lokana (slot 1-8).
class ImagePage extends StatefulWidget {
  const ImagePage({super.key});

  @override
  State<ImagePage> createState() => _ImagePageState();
}

enum _Source { emoji, file }

class _ImagePageState extends State<ImagePage> {
  static const quick = ['😊', '😂', '😍', '😎', '🥳', '😴', '👍', '❤️', '⭐', '🔥', '☕', '🎵', '🐱', '🌙', '⚡', '🍀'];
  final link = LokanaLink.instance;
  final ctrl = TextEditingController(text: '😊');

  _Source source = _Source.emoji;
  Effect effect = Effect.still;
  double threshold = 110, speedMs = 110;
  bool invert = false, dither = true, busy = false;
  int slot = 0, duration = 10;
  double progress = 0;

  ui.Image? glyph;                  // emoji/teks yang sudah dipotong rapat
  Uint8List? fileBytes;             // gambar/GIF pilihan
  Anim1? anim;                      // hasil yang dipratinjau & dikirim
  int _gen = 0;                     // render terbaru menang (hindari hasil lama menimpa)

  // Galeri di Lokana
  List<(int, int, int)>? slots;
  final thumbs = <int, Anim1>{};
  bool loadingGallery = false;

  @override
  void initState() {
    super.initState();
    _rebuildGlyph();
    _loadGallery();
  }

  @override
  void dispose() {
    ctrl.dispose();
    glyph?.dispose();
    super.dispose();
  }

  int get _w => link.info?.screenW ?? 128;
  int get _h => link.info?.screenH ?? 64;

  Future<void> _rebuildGlyph() async {
    final gen = ++_gen;
    final text = ctrl.text.trim();
    final g = text.isEmpty ? null : await renderGlyph(text);
    if (gen != _gen) { g?.dispose(); return; }
    glyph?.dispose();
    glyph = g;
    await _rebuildAnim();
  }

  Future<void> _rebuildAnim() async {
    final gen = ++_gen;
    Anim1? a;
    if (source == _Source.emoji) {
      final g = glyph;
      if (g != null) {
        a = await animateGlyph(g, effect,
            w: _w, h: _h, frameMs: speedMs.round(), threshold: threshold.round(), invert: invert);
      }
    } else if (fileBytes != null) {
      try {
        a = await decodeImageFile(fileBytes!,
            screenW: _w, screenH: _h, threshold: threshold.round(), invert: invert, dither: dither);
      } catch (_) {
        a = null;
      }
    }
    if (gen != _gen || !mounted) return;
    setState(() => anim = a);
  }

  Future<void> _pickFile() async {
    final b = await link.pickImage();
    if (b == null) return;
    setState(() { fileBytes = b; source = _Source.file; threshold = 128; });
    await _rebuildAnim();
    if (anim == null && mounted) _snack('Gambar tidak bisa dibaca');
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _send() async {
    final a = anim;
    if (a == null) return;
    setState(() { busy = true; progress = 0; });
    int st;
    if (link.hasAnim) {
      st = await link.sendAnim(a, slot: slot, durationS: slot == 0 ? duration : 0,
          onProgress: (p) => mounted ? setState(() => progress = p) : null);
    } else {                                       // firmware lama: bingkai pertama saja
      st = await link.send(T.bitmap, pBitmap(a.frames.first, op: slot == 0 ? 0 : 1, slot: slot,
          durationS: slot == 0 ? duration : 0));
    }
    if (!mounted) return;
    setState(() => busy = false);
    _snack(st == Status.ok ? (slot == 0 ? 'Tampil di Lokana' : 'Disimpan ke slot $slot') : Status.describe(st));
    if (st == Status.ok && slot != 0) _loadGallery();
  }

  Future<void> _loadGallery() async {
    if (!link.hasAnim || loadingGallery) return;
    setState(() => loadingGallery = true);
    final list = await link.listSlots();
    if (!mounted) return;
    setState(() { slots = list; thumbs.clear(); });
    if (list != null) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].$1 == 0) continue;
        final t = await link.readSlot(i + 1, firstOnly: true);
        if (!mounted) return;
        if (t != null) setState(() => thumbs[i + 1] = t);
      }
    }
    if (mounted) setState(() => loadingGallery = false);
  }

  Future<void> _openSlot(int s) async {
    final full = await showDialog<bool>(context: context, builder: (_) => _SlotDialog(slot: s, link: link));
    if (full == true) _loadGallery();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = anim;
    return Scaffold(
      appBar: AppBar(title: const Text('Emoji & Gambar')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        OledPreview(anim: a, screenW: _w, screenH: _h),
        const SizedBox(height: 6),
        Text(a == null ? 'Belum ada gambar'
            : '${a.frames.length} bingkai · ${a.w}x${a.h} · ${(a.totalBytes / 1024).toStringAsFixed(1)} KB'
              '${a.fits ? '' : ' · terlalu besar'}',
            style: t.bodySmall, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        SegmentedButton<_Source>(
          segments: const [
            ButtonSegment(value: _Source.emoji, icon: Icon(Icons.emoji_emotions_outlined), label: Text('Emoji / teks')),
            ButtonSegment(value: _Source.file, icon: Icon(Icons.image_outlined), label: Text('Gambar / GIF')),
          ],
          selected: {source},
          onSelectionChanged: (v) {
            setState(() { source = v.first; threshold = source == _Source.file ? 128 : 110; });
            if (source == _Source.file && fileBytes == null) { _pickFile(); } else { _rebuildAnim(); }
          },
        ),
        const SizedBox(height: 12),
        if (source == _Source.emoji) ...[
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final e in quick)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () { ctrl.text = e; _rebuildGlyph(); },
                child: Padding(padding: const EdgeInsets.all(6), child: Text(e, style: const TextStyle(fontSize: 28))),
              ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            maxLength: 24,
            onChanged: (_) => _rebuildGlyph(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Emoji atau teks',
              helperText: 'Emoji apa saja, huruf beraksen, atau gabungan seperti "Hai 👋"',
            ),
          ),
          const SizedBox(height: 8),
          Text('Animasi', style: t.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final fx in Effect.values)
              ChoiceChip(label: Text(fx.label), selected: effect == fx,
                  onSelected: (_) { setState(() => effect = fx); _rebuildAnim(); }),
          ]),
          if (effect != Effect.still) ...[
            const SizedBox(height: 8),
            Text('Kecepatan: ${speedMs.round()} ms/bingkai', style: t.titleSmall),
            Slider(value: speedMs, min: 50, max: 300, divisions: 25,
                onChanged: (v) => setState(() => speedMs = v), onChangeEnd: (_) => _rebuildAnim()),
          ],
        ] else ...[
          OutlinedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.folder_open),
            label: Text(fileBytes == null ? 'Pilih gambar atau GIF' : 'Ganti gambar'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Dithering (untuk foto)'),
            value: dither,
            onChanged: (v) { setState(() => dither = v); _rebuildAnim(); },
          ),
        ],
        Text('Ketajaman: ${threshold.round()}', style: t.titleSmall),
        Slider(value: threshold, min: 20, max: 235,
            onChanged: (v) => setState(() => threshold = v), onChangeEnd: (_) => _rebuildAnim()),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Balik warna'),
          value: invert,
          onChanged: (v) { setState(() => invert = v); _rebuildAnim(); },
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
        const SizedBox(height: 20),
        if (busy) LinearProgressIndicator(value: progress),
        const SizedBox(height: 4),
        FilledButton.icon(
          onPressed: a == null || busy || !a.fits ? null : _send,
          icon: Icon(slot == 0 ? Icons.send : Icons.save),
          label: Text(slot == 0 ? 'Kirim ke Lokana' : 'Simpan ke slot $slot'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        if (link.hasAnim) ...[
          const SizedBox(height: 28),
          Row(children: [
            Expanded(child: Text('Galeri di Lokana', style: t.titleMedium)),
            if (loadingGallery)
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            else
              IconButton(onPressed: _loadGallery, icon: const Icon(Icons.refresh), tooltip: 'Muat ulang'),
          ]),
          Text('Di Lokana: double-tap sampai modul Gambar, tap untuk berganti slot.', style: t.bodySmall),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.6,
            children: [
              for (var s = 1; s <= 8; s++)
                _SlotTile(
                  slot: s,
                  info: slots == null || slots!.length < s ? null : slots![s - 1],
                  thumb: thumbs[s],
                  onTap: () => _openSlot(s),
                ),
            ],
          ),
        ],
      ]),
    );
  }
}

class _SlotTile extends StatelessWidget {
  final int slot;
  final (int, int, int)? info;
  final Anim1? thumb;
  final VoidCallback onTap;
  const _SlotTile({required this.slot, this.info, this.thumb, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final empty = info == null || info!.$1 == 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: empty ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: empty
                  ? Center(child: Text('Kosong', style: t.bodySmall))
                  : thumb == null
                      ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                      : OledPreview(anim: thumb),
            ),
            const SizedBox(height: 4),
            Text(empty ? 'Slot $slot' : 'Slot $slot · ${info!.$1 > 1 ? '${info!.$1} bingkai' : 'gambar'}',
                style: t.labelSmall, textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }
}

/// Isi slot lengkap (animasi diputar) + tampilkan di Lokana / hapus. Hasil true = galeri berubah.
class _SlotDialog extends StatefulWidget {
  final int slot;
  final LokanaLink link;
  const _SlotDialog({required this.slot, required this.link});

  @override
  State<_SlotDialog> createState() => _SlotDialogState();
}

class _SlotDialogState extends State<_SlotDialog> {
  Anim1? anim;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    widget.link.readSlot(widget.slot).then((a) {
      if (mounted) setState(() { anim = a; loading = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = anim;
    return AlertDialog(
      title: Text('Slot ${widget.slot}'),
      content: SizedBox(
        width: 320,
        child: loading
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : Column(mainAxisSize: MainAxisSize.min, children: [
                OledPreview(anim: a),
                const SizedBox(height: 8),
                Text(a == null ? 'Tidak bisa dibaca' : '${a.frames.length} bingkai · ${a.frameMs} ms/bingkai'),
              ]),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await widget.link.deleteSlot(widget.slot);
            if (context.mounted) Navigator.pop(context, true);
          },
          child: const Text('Hapus'),
        ),
        FilledButton(
          onPressed: () async {
            await widget.link.showSlot(widget.slot, durationS: 10);
            if (context.mounted) Navigator.pop(context, false);
          },
          child: const Text('Tampilkan di Lokana'),
        ),
      ],
    );
  }
}
