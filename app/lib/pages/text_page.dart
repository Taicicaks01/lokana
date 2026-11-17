import 'package:material_ui/material_ui.dart';
import '../link/link.dart';
import '../link/proto.dart';
import '../main.dart';
import '../oled_text.dart';
import '../render.dart';
import '../theme.dart';
import '../ui.dart';

/// CUSTOM_TEXT: tulis teks, lihat pratinjau persis seperti di Lokana, lalu tampilkan sekarang atau simpan
/// ke slot 1-8 (name tag, pesan favorit). Slot yang tersimpan dibaca dari Lokana (TEXT_SLOT, 0.5.3).
class TextPage extends StatefulWidget {
  /// true = tampil di dalam tab (tanpa AppBar sendiri; judul dari tab).
  final bool embedded;
  const TextPage({super.key, this.embedded = false});

  @override
  State<TextPage> createState() => _TextPageState();
}

class _TextPageState extends State<TextPage> {
  final link = LokanaLink.instance;
  final prefs = AppTheme.instance;
  final ctrl = TextEditingController();
  late int style = prefs.prefInt('text_style', 0),
      size = prefs.prefInt('text_size', 0),
      font = prefs.prefInt('text_font', 0),
      duration = prefs.prefInt('text_duration', 0);
  int slot = 0;
  bool busy = false;

  List<TextSlot>? slots;
  bool loadingSlots = false;

  OledTextLayout? _layout;
  Anim1? _preview;
  String _previewKey = '';

  static const styles = {0: 'Diam', 1: 'Berjalan', 2: 'Berkedip'};
  static const sizes = {0: 'Otomatis', 1: 'Kecil', 2: 'Sedang', 3: 'Besar'};
  static const durations = {0: 'Sampai disentuh', 5: '5 dtk', 10: '10 dtk', 30: '30 dtk', 60: '1 mnt'};
  static const sizeName = {1: 'kecil', 2: 'sedang', 3: 'besar'};

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  bool get _fontsOk => versionAtLeast(link.info?.fwVersion ?? '0', '0.5.2');

  void _remember() {
    prefs.remember('text_style', style);
    prefs.remember('text_size', size);
    prefs.remember('text_font', font);
    prefs.remember('text_duration', duration);
  }

  /// Pratinjau dihitung ulang hanya saat isi/pilihan berubah.
  void _updatePreview() {
    final key = '${ctrl.text}|$style|$size|$font';
    if (key == _previewKey) return;
    _previewKey = key;
    final text = toLokanaAscii(ctrl.text.trim());
    if (text.isEmpty) { _layout = null; _preview = null; return; }
    _layout = OledTextLayout(text, style: style, size: size, font: _fontsOk ? font : 0,
        w: link.info?.screenW ?? 128, h: link.info?.screenH ?? 64);
    _preview = _layout!.toAnim(maxFrames: 240);
  }

  Future<void> _loadSlots() async {
    if (!link.hasTextSlots || loadingSlots) return;
    setState(() => loadingSlots = true);
    final s = await link.listTextSlots();
    if (mounted) setState(() { slots = s; loadingSlots = false; });
  }

  Future<void> _send() async {
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    _remember();
    setState(() => busy = true);
    final ok = await sendWithFeedback(
      context,
      T.customText,
      pCustomText(text, style: style, size: size, durationS: duration, slot: slot, font: font),
      ok: slot == 0 ? 'Tampil di Lokana' : 'Disimpan ke slot $slot',
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (ok && slot != 0) _loadSlots();
  }

  void _edit(TextSlot s) {
    setState(() {
      ctrl.text = s.text;
      style = s.style;
      size = s.size;
      font = s.font;
      slot = s.slot;
    });
  }

  Future<void> _openSlot(TextSlot s) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => _SlotSheet(slot: s),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'show':
        final st = await link.showTextSlot(s.slot, durationS: 10);
        if (mounted) showSnack(context, st == Status.ok ? 'Slot ${s.slot} tampil 10 detik' : Status.describe(st));
      case 'edit':
        _edit(s);
      case 'delete':
        final st = await link.deleteTextSlot(s.slot);
        if (!mounted) return;
        showSnack(context, st == Status.ok ? 'Slot ${s.slot} dikosongkan' : Status.describe(st));
        _loadSlots();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final warn = hasUnsupportedChars(ctrl.text);
    _updatePreview();
    final used = slots == null ? const <int>{} : {for (final s in slots!) if (!s.isEmpty) s.slot};

    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Teks')),
      bottomNavigationBar: ActionBar(
        label: slot == 0 ? 'Tampilkan di Lokana' : (used.contains(slot) ? 'Ganti isi slot $slot' : 'Simpan ke slot $slot'),
        icon: slot == 0 ? Icons.send_rounded : Icons.save_alt_rounded,
        onPressed: ctrl.text.trim().isEmpty ? null : _send,
        progress: busy ? 0 : null,
      ),
      body: PageBody(children: [
        // ---------- Pratinjau ----------
        _preview == null
            ? _EmptyPreview(text: 'Ketik sesuatu, pratinjaunya muncul di sini')
            : OledPreview(anim: _preview, screenW: link.info?.screenW ?? 128, screenH: link.info?.screenH ?? 64),
        const SizedBox(height: Gap.s),
        Text(
          _layout == null
              ? 'Pratinjau sama persis dengan layar Lokana'
              : 'Pratinjau persis Lokana · ukuran ${sizeName[_layout!.sizeUsed]}'
                  '${_layout!.vscroll ? ' · bergulir' : ''}',
          style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Gap.l),

        // ---------- Isi ----------
        TextField(
          controller: ctrl,
          maxLength: 200,
          minLines: 2,
          maxLines: 5,
          // Enter di keyboard = kirim (baris baru tidak dipakai; teks dibungkus otomatis di Lokana)
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _send(),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Contoh: Halo! Aku Lokana',
            helperText: warn ? 'Emoji & huruf khusus tampil sebagai "?". Untuk emoji, pakai Emoji & Gambar.' : null,
            helperMaxLines: 2,
            suffixIcon: ctrl.text.isEmpty
                ? null
                : IconButton(onPressed: () => setState(ctrl.clear), icon: const Icon(Icons.close), tooltip: 'Hapus'),
          ),
        ),

        // ---------- Tampilan ----------
        const SectionHeader('Tampilan', icon: Icons.tune),
        Panel(children: [
          Field('Font', first: true,
              help: _fontsOk ? null : 'Font selain Piksel perlu firmware Lokana 0.5.2.',
              child: Choices<int>(
                options: {for (final f in TextFont.all) f.id: f.label},
                value: font,
                styles: {
                  for (final f in TextFont.all)
                    f.id: TextStyle(fontFamily: f.preview,
                        fontWeight: f.label.contains('Tebal') ? FontWeight.w700 : FontWeight.w400),
                },
                onChanged: (v) => setState(() => font = v),
              )),
          Field('Ukuran huruf',
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [for (final e in sizes.entries) ButtonSegment(value: e.key, label: Text(e.value))],
                selected: {size},
                onSelectionChanged: (s) => setState(() => size = s.first),
              )),
          Field('Gaya',
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [for (final e in styles.entries) ButtonSegment(value: e.key, label: Text(e.value))],
                selected: {style},
                onSelectionChanged: (s) => setState(() => style = s.first),
              )),
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
                child: Choices<int>(options: durations, value: duration, onChanged: (v) => setState(() => duration = v)))
          else
            Padding(
              padding: const EdgeInsets.only(top: Gap.m),
              child: Text(
                  used.contains(slot)
                      ? 'Slot $slot sudah berisi. Menyimpan akan mengganti isinya.'
                      : 'Teks di slot tersimpan di Lokana walau dimatikan. Lihat di Lokana: double-tap sampai '
                          'modul Teks, lalu tap untuk berganti slot.',
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ),
        ]),

        // ---------- Slot tersimpan ----------
        SectionHeader(
          'Tersimpan di Lokana',
          icon: Icons.bookmarks_outlined,
          subtitle: 'Font, ukuran, dan gaya ikut tersimpan',
          trailing: link.hasTextSlots
              ? (loadingSlots
                  ? const Padding(padding: EdgeInsets.all(12),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(onPressed: _loadSlots, icon: const Icon(Icons.refresh), tooltip: 'Muat ulang'))
              : null,
        ),
        if (!link.hasTextSlots)
          const Notice('Perbarui firmware Lokana ke 0.5.3 untuk melihat isi slot di sini.', icon: Icons.system_update_alt)
        else if (slots == null && !loadingSlots)
          const Notice('Isi slot belum terbaca. Tekan muat ulang.', icon: Icons.sync_problem)
        else
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: Gap.s,
            crossAxisSpacing: Gap.s,
            childAspectRatio: 1.25,
            children: [
              for (var i = 1; i <= 8; i++)
                _TextSlotTile(
                  slot: slots == null || slots!.length < i ? null : slots![i - 1],
                  number: i,
                  onTap: slots == null ? null : () => _openSlot(slots![i - 1]),
                  onEmptyTap: () => setState(() => slot = i),
                ),
            ],
          ),
      ]),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  final String text;
  const _EmptyPreview({required this.text});

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 2,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24, width: 2),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(16),
          child: Text(text, style: const TextStyle(color: Colors.white54), textAlign: TextAlign.center),
        ),
      );
}

String _describe(TextSlot s) {
  final f = TextFont.all.firstWhere((f) => f.id == s.font, orElse: () => TextFont.all.first).label;
  const st = ['Diam', 'Berjalan', 'Berkedip'];
  const sz = ['Otomatis', 'Kecil', 'Sedang', 'Besar'];
  return '$f · ${sz[s.size.clamp(0, 3)]} · ${st[s.style.clamp(0, 2)]}';
}

class _TextSlotTile extends StatelessWidget {
  final TextSlot? slot;
  final int number;
  final VoidCallback? onTap, onEmptyTap;
  const _TextSlotTile({required this.slot, required this.number, this.onTap, this.onEmptyTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final s = slot;
    final empty = s == null || s.isEmpty;
    return Card(
      color: empty ? cs.surfaceContainerLowest : cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: empty ? BorderSide(color: cs.outlineVariant) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: s == null ? null : (empty ? onEmptyTap : onTap),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: s == null
                  ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                  : empty
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.add, color: cs.outline),
                          Text('Kosong', style: t.bodySmall?.copyWith(color: cs.outline)),
                        ]))
                      : OledPreview(anim: Anim1(128, 64, [
                          // teks berjalan: bingkai saat awal teks tepat di tepi kiri layar
                          OledTextLayout(s.text, style: s.style == 1 ? 1 : 0, size: s.size, font: s.font)
                              .draw(s.style == 1 ? 128 * 12 : 0),
                        ])),
            ),
            const SizedBox(height: 6),
            Text('Slot $number', style: t.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
            Text(empty ? 'Ketuk untuk memilih' : _describe(s), style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}

class _SlotSheet extends StatelessWidget {
  final TextSlot slot;
  const _SlotSheet({required this.slot});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final layout = OledTextLayout(slot.text, style: slot.style, size: slot.size, font: slot.font);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Slot ${slot.slot}', style: t.titleLarge),
          Text(_describe(slot), style: t.bodySmall),
          const SizedBox(height: Gap.m),
          OledPreview(anim: layout.toAnim(maxFrames: 240)),
          const SizedBox(height: Gap.m),
          Text(slot.text, style: t.bodyMedium, maxLines: 4, overflow: TextOverflow.ellipsis),
          const SizedBox(height: Gap.l),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, 'show'),
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Tampilkan di Lokana'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: Gap.s),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'edit'),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Ubah'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ),
            const SizedBox(width: Gap.s),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'delete'),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Kosongkan'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48), foregroundColor: Theme.of(context).colorScheme.error),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
