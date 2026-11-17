import 'package:material_ui/material_ui.dart';
import '../link/link.dart';
import '../link/proto.dart';
import '../theme.dart';
import '../ui.dart';

/// Cari HP (tab Terhubung): cara memanggil HP dari Lokana + nada yang dibunyikan HP ini (`Alarm.kt`).
/// Dipindah dari Pengaturan (DESIGN.md §3).
class FindPhonePage extends StatefulWidget {
  /// true = tampil di dalam tab (tanpa AppBar sendiri; judul dari tab).
  final bool embedded;
  const FindPhonePage({super.key, this.embedded = false});

  @override
  State<FindPhonePage> createState() => _FindPhonePageState();
}

class _FindPhonePageState extends State<FindPhonePage> {
  final link = LokanaLink.instance;
  String? ringtone;

  @override
  void initState() {
    super.initState();
    link.ringtoneTitle().then((t) => mounted ? setState(() => ringtone = t) : null);
  }

  @override
  void dispose() {
    link.stopRingtonePreview();
    super.dispose();
  }

  Future<void> _pick({bool file = false}) async {
    final t = await link.pickRingtone(file: file);
    if (t != null && mounted) setState(() => ringtone = t);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final lk = context.lk;
    final supported = link.info?.has(Caps.findPhone) ?? true;
    const steps = [
      (Icons.swipe_right_alt_rounded, 'Di Lokana, tap 2× sampai modul Cari HP'),
      (Icons.touch_app_outlined, 'Tap sekali: HP ini berbunyi keras, walau sedang senyap'),
      (Icons.check_circle_outline, 'Tekan "Ketemu" di HP, atau tap Lokana lagi untuk berhenti'),
    ];
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Cari HP')),
      body: PageBody(children: [
        // ---------- Cara memanggil ----------
        Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          decoration: BoxDecoration(color: lk.hero, borderRadius: BorderRadius.circular(LokanaTokens.rHero)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconBadge(Icons.phonelink_ring_rounded, background: lk.pinkSoft, color: lk.pink),
              const SizedBox(width: Gap.m),
              Expanded(child: Text('HP-mu di mana?', style: t.titleLarge?.copyWith(color: Colors.white))),
            ]),
            const SizedBox(height: Gap.m),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: Text('${i + 1}',
                        style: t.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: Gap.m),
                  Icon(steps[i].$1, size: 18, color: Colors.white54),
                  const SizedBox(width: Gap.s),
                  Expanded(child: Text(steps[i].$2, style: t.bodyMedium?.copyWith(color: Colors.white))),
                ]),
              ),
          ]),
        ),
        if (!supported) ...[
          const SizedBox(height: Gap.m),
          const Notice('Firmware Lokana ini belum mendukung Cari HP. Perbarui Lokana OS.',
              icon: Icons.system_update_alt, warning: true),
        ],

        // ---------- Nada ----------
        const SectionHeader('Nada di HP ini', icon: Icons.ring_volume_outlined, subtitle: 'Disimpan di HP ini'),
        Panel(children: [
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
                onPressed: _pick, icon: const Icon(Icons.library_music_outlined), label: const Text('Nada HP')),
            OutlinedButton.icon(
                onPressed: () => _pick(file: true),
                icon: const Icon(Icons.audio_file_outlined),
                label: const Text('File audio')),
            TextButton(
              onPressed: () async {
                final r = await link.resetRingtone();
                if (r != null && mounted) setState(() => ringtone = r);
              },
              child: const Text('Bawaan'),
            ),
          ]),
          const SizedBox(height: Gap.s),
          Text('Volume alarm dinaikkan penuh selama berbunyi, lalu dikembalikan. Kalau file audio terhapus, '
              'nada alarm HP yang dipakai.', style: t.bodySmall),
        ]),
      ]),
    );
  }
}
