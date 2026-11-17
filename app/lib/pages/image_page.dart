import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import '../link/link.dart';
import '../link/proto.dart';
import '../render.dart';
import '../theme.dart';
import '../ui.dart';

/// Emoji, teks, gambar & GIF -> animasi 1-bit; kirim sekarang atau simpan ke galeri Lokana (slot 1-8).
class ImagePage extends StatefulWidget {
  /// true = tampil di dalam tab (tanpa AppBar sendiri; judul dari tab).
  final bool embedded;
  const ImagePage({super.key, this.embedded = false});

  @override
  State<ImagePage> createState() => _ImagePageState();
}

enum _Source { emoji, file }

class _ImagePageState extends State<ImagePage> {
  static const quick = ['😊', '😂', '😍', '😎', '🥳', '😴', '👍', '❤️', '⭐', '🔥', '☕', '🎵', '🐱', '🌙', '⚡', '🍀'];
  final link = LokanaLink.instance;
  final prefs = AppTheme.instance;
  final ctrl = TextEditingController(text: '😊');

  // Setelan terakhir diingat di HP (bukan di Lokana): yang dikirim ke Lokana adalah hasil gambarnya.
  _Source source = _Source.emoji;
  late Effect effect = Effect.values.firstWhere((e) => e.name == prefs.pref('img_effect'), orElse: () => Effect.still);
  late double threshold = prefs.prefInt('img_threshold_emoji', 110).toDouble(),
      speedMs = prefs.prefInt('img_speed', 110).toDouble();
  late bool invert = prefs.prefBool('img_invert', false), dither = prefs.prefBool('img_dither', true);
  bool busy = false;
  int slot = 0;
  late int duration = prefs.prefInt('img_duration', 10);
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
    setState(() {
      fileBytes = b;
      source = _Source.file;
      threshold = prefs.prefInt('img_threshold_file', 128).toDouble();
    });
    await _rebuildAnim();
    if (anim == null && mounted) _snack('Gambar tidak bisa dibaca');
  }

  void _snack(String m) => showSnack(context, m);

  void _remember() {
    prefs.remember('img_effect', effect.name);
    prefs.remember(source == _Source.file ? 'img_threshold_file' : 'img_threshold_emoji', threshold.round());
    prefs.remember('img_speed', speedMs.round());
    prefs.remember('img_invert', invert);
    prefs.remember('img_dither', dither);
    prefs.remember('img_duration', duration);
  }

  Future<void> _send() async {
    final a = anim;
    if (a == null) return;
    _remember();
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
    final cs = Theme.of(context).colorScheme;
    final a = anim;
    final used = slots == null ? const <int>{} : {for (var i = 0; i < slots!.length; i++) if (slots![i].$1 > 0) i + 1};
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Emoji & Gambar')),
      bottomNavigationBar: ActionBar(
        label: slot == 0 ? 'Tampilkan di Lokana' : (used.contains(slot) ? 'Ganti isi slot $slot' : 'Simpan ke slot $slot'),
        icon: slot == 0 ? Icons.send_rounded : Icons.save_alt_rounded,
        onPressed: a == null || !a.fits ? null : _send,
        progress: busy ? progress : null,
      ),
      body: PageBody(children: [
        OledPreview(anim: a, screenW: _w, screenH: _h),
        const SizedBox(height: Gap.s),
        Text(a == null ? 'Belum ada gambar'
            : '${a.frames.length} bingkai · ${a.w}x${a.h} · ${(a.totalBytes / 1024).toStringAsFixed(1)} KB'
              '${a.fits ? '' : ' · terlalu besar'}',
            style: t.bodySmall?.copyWith(color: a != null && !a.fits ? cs.error : cs.onSurfaceVariant),
            textAlign: TextAlign.center),
        const SizedBox(height: Gap.l),
        SegmentedButton<_Source>(
          segments: const [
            ButtonSegment(value: _Source.emoji, icon: Icon(Icons.emoji_emotions_outlined), label: Text('Emoji / teks')),
            ButtonSegment(value: _Source.file, icon: Icon(Icons.image_outlined), label: Text('Gambar / GIF')),
          ],
          selected: {source},
          onSelectionChanged: (v) {
            setState(() {
              source = v.first;
              threshold = prefs.prefInt(source == _Source.file ? 'img_threshold_file' : 'img_threshold_emoji',
                  source == _Source.file ? 128 : 110).toDouble();
            });
            if (source == _Source.file && fileBytes == null) { _pickFile(); } else { _rebuildAnim(); }
          },
        ),

        // ---------- Sumber ----------
        SectionHeader(source == _Source.emoji ? 'Emoji atau teks' : 'Gambar', icon: Icons.brush_outlined),
        Panel(children: [
          if (source == _Source.emoji) ...[
            GridView.count(
              crossAxisCount: 8,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final e in quick)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () { ctrl.text = e; _rebuildGlyph(); },
                    child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
                  ),
              ],
            ),
            const SizedBox(height: Gap.s),
            TextField(
              controller: ctrl,
              maxLength: 24,
              onChanged: (_) => _rebuildGlyph(),
              decoration: const InputDecoration(
                hintText: 'Emoji, huruf, atau "Hai 👋"',
                helperText: 'Emoji apa saja, huruf beraksen, atau gabungan',
              ),
            ),
          ] else ...[
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.folder_open),
              label: Text(fileBytes == null ? 'Pilih gambar atau GIF' : 'Ganti gambar'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dithering'),
              subtitle: const Text('Titik-titik halus untuk foto. Matikan untuk logo & gambar garis.'),
              value: dither,
              onChanged: (v) { setState(() => dither = v); _rebuildAnim(); },
            ),
          ],
        ]),

        // ---------- Tampilan ----------
        const SectionHeader('Tampilan', icon: Icons.tune),
        Panel(children: [
          if (source == _Source.emoji) ...[
            Field('Animasi', first: true,
                child: Choices<Effect>(
                  options: {for (final fx in Effect.values) fx: fx.label},
                  value: effect,
                  onChanged: (fx) { setState(() => effect = fx); _rebuildAnim(); },
                )),
            if (effect != Effect.still)
              Field('Kecepatan: ${speedMs.round()} ms/bingkai',
                  child: Slider(value: speedMs, min: 50, max: 300, divisions: 25,
                      onChanged: (v) => setState(() => speedMs = v), onChangeEnd: (_) => _rebuildAnim())),
          ],
          Field('Ketajaman: ${threshold.round()}', first: source == _Source.file,
              help: 'Batas terang piksel yang menyala. Geser sampai pratinjau paling jelas.',
              child: Slider(value: threshold, min: 20, max: 235,
                  onChanged: (v) => setState(() => threshold = v), onChangeEnd: (_) => _rebuildAnim())),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Balik warna'),
            value: invert,
            onChanged: (v) { setState(() => invert = v); _rebuildAnim(); },
          ),
        ]),

        // ---------- Tujuan ----------
        const SectionHeader('Kirim ke', icon: Icons.outbox_outlined),
        Panel(children: [
          Choices<int>(
            options: {0: 'Tampilkan sekarang', for (var s = 1; s <= 8; s++) s: used.contains(s) ? 'Slot $s •' : 'Slot $s'},
            value: slot,
            onChanged: (v) => setState(() => slot = v),
          ),
          if (slot == 0)
            Field('Lama tampil',
                child: Choices<int>(
                  options: const {5: '5 dtk', 10: '10 dtk', 30: '30 dtk', 0: 'Sampai disentuh'},
                  value: duration,
                  onChanged: (v) => setState(() => duration = v),
                ))
          else
            Padding(
              padding: const EdgeInsets.only(top: Gap.m),
              child: Text('Yang disimpan adalah hasil gambar seperti di pratinjau (termasuk ketajaman, warna, '
                  'dan kecepatan animasi).${used.contains(slot) ? ' Isi slot $slot akan diganti.' : ''}',
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
        ]),

        // ---------- Galeri ----------
        if (link.hasAnim) ...[
          SectionHeader(
            'Galeri di Lokana',
            icon: Icons.photo_library_outlined,
            subtitle: 'Di Lokana: double-tap sampai modul Gambar, tap untuk berganti slot',
            trailing: loadingGallery
                ? const Padding(padding: EdgeInsets.all(12),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : IconButton(onPressed: _loadGallery, icon: const Icon(Icons.refresh), tooltip: 'Muat ulang'),
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: Gap.s,
            crossAxisSpacing: Gap.s,
            childAspectRatio: 1.25,
            children: [
              for (var s = 1; s <= 8; s++)
                _SlotTile(
                  slot: s,
                  info: slots == null || slots!.length < s ? null : slots![s - 1],
                  thumb: thumbs[s],
                  onTap: () => _openSlot(s),
                  onEmptyTap: () => setState(() => slot = s),
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
  final VoidCallback onTap, onEmptyTap;
  const _SlotTile({required this.slot, this.info, this.thumb, required this.onTap, required this.onEmptyTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final loading = info == null;
    final empty = !loading && info!.$1 == 0;
    return Card(
      color: empty ? cs.surfaceContainerLowest : cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: empty ? BorderSide(color: cs.outlineVariant) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: loading ? null : (empty ? onEmptyTap : onTap),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: empty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add, color: cs.outline),
                      Text('Kosong', style: t.bodySmall?.copyWith(color: cs.outline)),
                    ]))
                  : thumb == null
                      ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                      : OledPreview(anim: thumb),
            ),
            const SizedBox(height: 6),
            Text('Slot $slot', style: t.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
            Text(
                loading ? '...' : empty ? 'Ketuk untuk memilih' : (info!.$1 > 1 ? 'Animasi · ${info!.$1} bingkai' : 'Gambar'),
                style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
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
