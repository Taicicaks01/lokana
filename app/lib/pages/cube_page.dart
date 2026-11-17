import 'package:material_ui/material_ui.dart';
import '../cube.dart';
import '../theme.dart';
import '../ui.dart';

/// Pratinjau Lokana Cube dan keempat mood-nya (Pengaturan → Tentang). Untuk mengecek gambar & gerak di HP
/// sebelum Lokana Cube dipakai di Beranda, Sambungkan, dan Pengaturan.
class CubePage extends StatefulWidget {
  const CubePage({super.key});

  @override
  State<CubePage> createState() => _CubePageState();
}

class _CubePageState extends State<CubePage> {
  CubeMood mood = CubeMood.idle;

  static const labels = {
    CubeMood.idle: ('Siaga', 'Terhubung, berkedip acak'),
    CubeMood.mencari: ('Mencari', 'Melirik kiri-kanan'),
    CubeMood.mengantuk: ('Mengantuk', 'Terputus / menyambung ulang'),
    CubeMood.senang: ('Senang', 'Perintah berhasil'),
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final lk = context.lk;
    return Scaffold(
      appBar: AppBar(title: const Text('Lokana Cube')),
      body: PageBody(children: [
        // Satu cube yang bisa diganti mood-nya: cek transisi
        Container(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
          decoration: BoxDecoration(color: lk.hero, borderRadius: BorderRadius.circular(LokanaTokens.rHero)),
          child: Column(children: [
            LokanaCube(scale: 1.3, mood: mood),
            const SizedBox(height: Gap.l),
            Text(labels[mood]!.$1, style: t.titleLarge?.copyWith(color: Colors.white)),
            Text(labels[mood]!.$2, style: t.bodySmall?.copyWith(color: Colors.white70)),
          ]),
        ),
        const SizedBox(height: Gap.m),
        SegmentedButton<CubeMood>(
          showSelectedIcon: false,
          segments: [
            for (final m in CubeMood.values) ButtonSegment(value: m, label: Text(labels[m]!.$1)),
          ],
          selected: {mood},
          onSelectionChanged: (v) => setState(() => mood = v.first),
        ),
        const SectionHeader('Semua mood', icon: Icons.mood_outlined),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.95,
          children: [
            for (final m in CubeMood.values)
              Card(
                color: lk.hero,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  LokanaCube(scale: 0.75, mood: m),
                  const SizedBox(height: Gap.s),
                  Text(labels[m]!.$1, style: t.labelLarge?.copyWith(color: Colors.white)),
                ]),
              ),
          ],
        ),
        const SectionHeader('Ukuran', icon: Icons.straighten),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, crossAxisAlignment: CrossAxisAlignment.end,
                children: const [
                  LokanaCube(scale: 0.3),
                  LokanaCube(scale: 0.5),
                  LokanaCube(scale: 0.8),
                ]),
          ),
        ),
        const SizedBox(height: Gap.s),
        Text('Warna mata mengikuti "Warna layar di pratinjau" di Pengaturan.',
            style: t.bodySmall, textAlign: TextAlign.center),
      ]),
    );
  }
}
