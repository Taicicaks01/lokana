// Kerangka utama saat Lokana tersambung: 4 tab (docs/DESIGN.md §3).
// Beranda · Studio · Terhubung · Pengaturan. Belum tersambung = ConnectPage tanpa tab (lihat HomePage).
import 'package:material_ui/material_ui.dart';
import 'pages/dashboard_page.dart';
import 'pages/dice_page.dart';
import 'pages/expression_page.dart';
import 'pages/find_phone_page.dart';
import 'pages/image_page.dart';
import 'pages/leave_page.dart';
import 'pages/notif_page.dart';
import 'pages/settings_page.dart';
import 'pages/text_page.dart';

/// Nomor tab dan segmen, untuk [ShellNav.go].
class Tabs {
  static const home = 0, studio = 1, link = 2, settings = 3;
}

class StudioSeg {
  static const teks = 0, gambar = 1, ekspresi = 2, dadu = 3;
}

/// Pindah tab dari halaman di dalam kerangka, misalnya kisi Studio di Beranda → tab Studio segmen Gambar.
class ShellNav extends InheritedWidget {
  final void Function(int tab, {int? segment}) go;
  const ShellNav({super.key, required this.go, required super.child});

  static ShellNav? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ShellNav>();

  @override
  bool updateShouldNotify(ShellNav old) => false;
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int tab = Tabs.home;
  // Tab dibuat saat pertama dibuka, lalu dipertahankan (isian & gulir tidak hilang saat berpindah tab)
  final _built = <int>{Tabs.home};
  final _studioSeg = ValueNotifier<int>(StudioSeg.teks);
  final _linkSeg = ValueNotifier<int>(0);

  static const _tabs = [
    NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Beranda'),
    NavigationDestination(icon: Icon(Icons.brush_outlined), selectedIcon: Icon(Icons.brush_rounded), label: 'Studio'),
    NavigationDestination(icon: Icon(Icons.sensors_outlined), selectedIcon: Icon(Icons.sensors_rounded), label: 'Terhubung'),
    NavigationDestination(
        icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'Pengaturan'),
  ];

  @override
  void dispose() {
    _studioSeg.dispose();
    _linkSeg.dispose();
    super.dispose();
  }

  Widget _page(int i) => switch (i) {
        Tabs.home => const DashboardPage(),
        Tabs.studio => _SegmentTab(title: 'Studio', selected: _studioSeg, segments: const [
            ('Teks', TextPage(embedded: true)),
            ('Gambar', ImagePage(embedded: true)),
            ('Ekspresi', ExpressionPage(embedded: true)),
            ('Dadu', DicePage(embedded: true)),
          ]),
        Tabs.link => _SegmentTab(title: 'Terhubung', selected: _linkSeg, segments: const [
            ('Ketinggalan', LeavePage(embedded: true)),
            ('Notifikasi', NotifPage(embedded: true)),
            ('Cari HP', FindPhonePage(embedded: true)),
          ]),
        _ => const SettingsPage(),
      };

  void _go(int i, {int? segment}) => setState(() {
        if (segment != null) (i == Tabs.studio ? _studioSeg : _linkSeg).value = segment;
        tab = i;
        _built.add(i);
      });

  @override
  Widget build(BuildContext context) {
    // Tombol kembali Android di tab lain = kembali ke Beranda dulu
    return ShellNav(
      go: _go,
      child: PopScope(
        canPop: tab == Tabs.home,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _go(Tabs.home);
        },
        child: Scaffold(
          body: IndexedStack(
            index: tab,
            children: [for (var i = 0; i < _tabs.length; i++) _built.contains(i) ? _page(i) : const SizedBox.shrink()],
          ),
          bottomNavigationBar:
              NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => _go(i), destinations: _tabs),
        ),
      ),
    );
  }
}

/// Tab berisi beberapa halaman yang dipilih lewat SegmentedButton (Studio, Terhubung).
class _SegmentTab extends StatefulWidget {
  final String title;
  final List<(String, Widget)> segments;
  final ValueNotifier<int> selected;
  const _SegmentTab({required this.title, required this.segments, required this.selected});

  @override
  State<_SegmentTab> createState() => _SegmentTabState();
}

class _SegmentTabState extends State<_SegmentTab> {
  // Halaman dibuat saat pertama dipilih (hindari banyak permintaan BLE sekaligus)
  late final _built = <int>{widget.selected.value};

  void _changed() => setState(() => _built.add(widget.selected.value));

  @override
  void initState() {
    super.initState();
    widget.selected.addListener(_changed);
  }

  @override
  void dispose() {
    widget.selected.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seg = widget.selected.value;
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
                onSelectionChanged: (v) => widget.selected.value = v.first,
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
