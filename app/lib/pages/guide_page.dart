import 'package:material_ui/material_ui.dart';
import '../link/link.dart';
import '../link/proto.dart';
import '../main.dart';
import '../theme.dart';
import '../ui.dart';

/// Cara pakai Lokana: gerakan, modul, menu, plus setelan Panduan di layar Lokana (SETTINGS boot_guide).
class GuidePage extends StatefulWidget {
  const GuidePage({super.key});

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  final link = LokanaLink.instance;

  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    link.addListener(_changed);
    if (link.ready) link.send(T.settings, pSettingsGet());
  }

  @override
  void dispose() {
    link.removeListener(_changed);
    super.dispose();
  }

  static const gestures = [
    (Icons.touch_app_outlined, 'Tap', 'Aksi di modul yang sedang tampil: colek wajah, lempar dadu, ganti slot.'),
    (Icons.swipe_right_alt_outlined, 'Tap 2x', 'Pindah ke modul berikutnya.'),
    (Icons.menu_rounded, 'Tap 3x', 'Buka menu pengaturan di Lokana.'),
    (Icons.back_hand_outlined, 'Tahan', 'Di menu: ubah atau pilih. Di luar menu: layar tidur. Sentuh lagi untuk bangun.'),
  ];

  static const modules = [
    (Icons.remove_red_eye_outlined, 'Lokana', 'Wajah & ekspresi. Tap = colek.'),
    (Icons.schedule, 'Jam', 'Jam & tanggal dari HP. Tap = tampilkan detik.'),
    (Icons.notifications_outlined, 'Notif', 'Notifikasi terakhir. Tap = notifikasi berikutnya.'),
    (Icons.phonelink_ring_outlined, 'Cari HP', 'Tap = bunyikan HP yang tersambung, tap lagi = berhenti.'),
    (Icons.casino_outlined, 'Dadu', 'Tap = lempar. Jenis dadu dipilih dari aplikasi.'),
    (Icons.text_fields, 'Teks', 'Teks & name tag. Tap = slot berikutnya.'),
    (Icons.image_outlined, 'Gambar', 'Gambar & animasi tersimpan. Tap = slot berikutnya.'),
  ];

  static const menu = [
    ('Kecerahan', 'Redup, sedang, terang'),
    ('Suara', 'Bunyi tombol & efek'),
    ('Layar mati', 'Setelah 15 dtk sampai tidak pernah'),
    ('Putar layar', 'Balik 180° untuk dipasang terbalik'),
    ('Panduan', 'Putar panduan ini, atau atur tampil saat menyala'),
    ('Lupakan HP', 'Hapus pairing'),
    ('Info', 'Versi, jam, Bluetooth'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final s = link.ready ? link.settings : null;
    final guideOk = link.ready && s?.bootGuide != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Cara pakai Lokana')),
      body: PageBody(children: [
        // ---------- Pembuka ----------
        Card(
          color: Colors.black,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(children: [
              LokanaEyes(color: AppTheme.instance.oled.color, height: 48),
              const SizedBox(height: Gap.l),
              Text('Satu sensor, empat gerakan', style: t.titleLarge?.copyWith(color: Colors.white)),
              const SizedBox(height: Gap.xs),
              Text('Semua dikendalikan dengan menyentuh sensor di Lokana. Hal yang lebih lengkap diatur dari aplikasi ini.',
                  style: t.bodySmall?.copyWith(color: Colors.white70), textAlign: TextAlign.center),
            ]),
          ),
        ),

        // ---------- Gerakan ----------
        const SectionHeader('Gerakan', icon: Icons.gesture),
        Panel(padding: const EdgeInsets.symmetric(vertical: 8), children: [
          for (final g in gestures)
            ListTile(
              leading: IconBadge(g.$1, size: 40),
              title: Text(g.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(g.$3),
            ),
        ]),

        // ---------- Modul ----------
        const SectionHeader('Modul', icon: Icons.view_carousel_outlined, subtitle: 'Berganti dengan tap 2x, berurutan'),
        Panel(padding: const EdgeInsets.symmetric(vertical: 8), children: [
          for (var i = 0; i < modules.length; i++)
            ListTile(
              leading: IconBadge(modules[i].$1, size: 40,
                  background: cs.secondaryContainer, color: cs.onSecondaryContainer),
              title: Text('${i + 1}. ${modules[i].$2}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(modules[i].$3),
            ),
        ]),

        // ---------- Menu ----------
        const SectionHeader('Menu di Lokana', icon: Icons.menu_open, subtitle: 'Tap 3x untuk membuka'),
        Panel(children: [
          Text('Tap = item berikutnya · Tahan = ubah/pilih · Tap 2x = keluar', style: t.bodySmall),
          const SizedBox(height: Gap.s),
          for (final m in menu)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 110, child: Text(m.$1, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                Expanded(child: Text(m.$2, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
              ]),
            ),
        ]),

        // ---------- Panduan di Lokana ----------
        const SectionHeader('Panduan di layar Lokana', icon: Icons.slideshow_outlined),
        Panel(children: [
          Text('Setelah animasi pembuka, Lokana bisa memperagakan keempat gerakan di layarnya (±17 detik). '
              'Sentuh Lokana untuk melewatinya.', style: t.bodySmall),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tampilkan setelah menyala'),
            subtitle: Text(!link.ready
                ? 'Sambungkan Lokana untuk mengatur'
                : s == null
                    ? 'Membaca pengaturan...'
                    : s.bootGuide == null
                        ? 'Perlu firmware Lokana 0.5.3'
                        : 'Bisa juga dari menu Lokana: Panduan > Saat boot'),
            value: s?.bootGuide ?? false,
            onChanged: guideOk ? (v) => sendWithFeedback(context, T.settings, pSettingsSet(bootGuide: v)) : null,
          ),
          const SizedBox(height: Gap.xs),
          FilledButton.tonalIcon(
            onPressed: guideOk
                ? () => sendWithFeedback(context, T.goto, pGoto('Panduan'), ok: 'Panduan diputar di Lokana')
                : null,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Putar di Lokana sekarang'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ]),

        // ---------- Tips ----------
        const SectionHeader('Tips', icon: Icons.lightbulb_outline),
        Panel(children: [
          for (final tip in const [
            'Lokana hilang? Di aplikasi, tekan Cari kunci: Lokana berbunyi 30 detik.',
            'HP hilang? Di Lokana buka modul Cari HP lalu tap: HP berbunyi walau sedang senyap.',
            'Pergi tanpa Lokana? HP berbunyi. Pergi tanpa HP? Lokana berbunyi. Atur di Pengingat ketinggalan.',
            'Teks & gambar di slot tetap tersimpan walau Lokana dimatikan.',
            'Layar Lokana di aplikasi menampilkan isi layar langsung dan bisa dipakai sebagai remote.',
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 6), child: Icon(Icons.circle, size: 6, color: cs.primary)),
                const SizedBox(width: Gap.s),
                Expanded(child: Text(tip, style: t.bodyMedium)),
              ]),
            ),
        ]),
      ]),
    );
  }
}
