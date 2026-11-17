// Kerangka utama saat Lokana tersambung: 4 tab (docs/DESIGN.md §3).
// Beranda · Studio · Terhubung · Pengaturan. Belum tersambung = ConnectPage tanpa tab (lihat HomePage).
import 'package:material_ui/material_ui.dart';
import 'pages/dashboard_page.dart';
import 'pages/dice_page.dart';
import 'pages/expression_page.dart';
import 'pages/image_page.dart';
import 'pages/leave_page.dart';
import 'pages/notif_page.dart';
import 'pages/settings_page.dart';
import 'pages/text_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int tab = 0;
  // Tab dibuat saat pertama dibuka, lalu dipertahankan (isian & gulir tidak hilang saat berpindah tab)
  final _built = <int>{0};

  static const _tabs = [
    NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Beranda'),
    NavigationDestination(icon: Icon(Icons.brush_outlined), selectedIcon: Icon(Icons.brush_rounded), label: 'Studio'),
    NavigationDestination(icon: Icon(Icons.sensors_outlined), selectedIcon: Icon(Icons.sensors_rounded), label: 'Terhubung'),
    NavigationDestination(
        icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'Pengaturan'),
  ];

  Widget _page(int i) => switch (i) {
        0 => const DashboardPage(),
        1 => const _SegmentTab(title: 'Studio', segments: [
            ('Teks', TextPage(embedded: true)),
            ('Gambar', ImagePage(embedded: true)),
            ('Ekspresi', ExpressionPage(embedded: true)),
            ('Dadu', DicePage(embedded: true)),
          ]),
        2 => const _SegmentTab(title: 'Terhubung', segments: [
            ('Ketinggalan', LeavePage(embedded: true)),
            ('Notifikasi', NotifPage(embedded: true)),
          ]),
        _ => const SettingsPage(),
      };

  void _go(int i) => setState(() {
        tab = i;
        _built.add(i);
      });

  @override
  Widget build(BuildContext context) {
    // Tombol kembali Android di tab lain = kembali ke Beranda dulu
    return PopScope(
      canPop: tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: tab,
          children: [for (var i = 0; i < _tabs.length; i++) _built.contains(i) ? _page(i) : const SizedBox.shrink()],
        ),
        bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: _go, destinations: _tabs),
      ),
    );
  }
}

/// Tab berisi beberapa halaman yang dipilih lewat SegmentedButton (Studio, Terhubung).
class _SegmentTab extends StatefulWidget {
  final String title;
  final List<(String, Widget)> segments;
  const _SegmentTab({required this.title, required this.segments});

  @override
  State<_SegmentTab> createState() => _SegmentTabState();
}

class _SegmentTabState extends State<_SegmentTab> {
  int seg = 0;
  final _built = <int>{0};   // halaman dibuat saat pertama dipilih (hindari banyak permintaan BLE sekaligus)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  for (var i = 0; i < widget.segments.length; i++)
                    ButtonSegment(value: i, label: Text(widget.segments[i].$1, maxLines: 1, softWrap: false)),
                ],
                selected: {seg},
                onSelectionChanged: (v) => setState(() {
                  seg = v.first;
                  _built.add(seg);
                }),
              ),
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: seg,
        children: [
          for (var i = 0; i < widget.segments.length; i++)
            _built.contains(i) ? widget.segments[i].$2 : const SizedBox.shrink(),
        ],
      ),
    );
  }
}
