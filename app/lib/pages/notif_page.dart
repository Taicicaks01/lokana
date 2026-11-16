import 'package:material_ui/material_ui.dart';
import '../link/link.dart';
import '../link/proto.dart';

/// Penerusan notifikasi & panggilan ke Lokana. Hanya aplikasi yang dicentang yang diteruskan.
class NotifPage extends StatefulWidget {
  const NotifPage({super.key});

  @override
  State<NotifPage> createState() => _NotifPageState();
}

class _NotifPageState extends State<NotifPage> with WidgetsBindingObserver {
  final link = LokanaLink.instance;
  NotifStatus? status;
  List<AppEntry>? apps;
  String query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    link.installedApps().then((a) => mounted ? setState(() => apps = a) : null);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Kembali dari Pengaturan Android (izin akses notifikasi / baterai): baca ulang status
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await link.notifStatus();
    if (mounted) setState(() => status = s);
  }

  Future<void> _test() async {
    final st = await link.testNotif();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(st == Status.ok ? 'Notifikasi uji terkirim ke Lokana' : Status.describe(st))));
  }

  @override
  Widget build(BuildContext context) {
    final s = status;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    if (s == null) {
      return Scaffold(appBar: AppBar(title: const Text('Notifikasi')),
          body: const Center(child: CircularProgressIndicator()));
    }
    final q = query.toLowerCase();
    final shown = (apps ?? const <AppEntry>[])
        .where((a) => q.isEmpty || a.label.toLowerCase().contains(q) || a.package.contains(q))
        .toList()
      ..sort((a, b) {
        final sa = s.apps.contains(a.package), sb = s.apps.contains(b.package);
        return sa == sb ? a.label.toLowerCase().compareTo(b.label.toLowerCase()) : (sa ? -1 : 1);
      });

    return Scaffold(
      appBar: AppBar(title: const Text('Notifikasi')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (!s.access)
          Card(
            color: cs.errorContainer,
            child: ListTile(
              leading: Icon(Icons.notifications_off_outlined, color: cs.onErrorContainer),
              title: Text('Izinkan akses notifikasi', style: TextStyle(color: cs.onErrorContainer)),
              subtitle: Text('Aktifkan "Lokana" di daftar akses notifikasi Android.',
                  style: TextStyle(color: cs.onErrorContainer)),
              trailing: FilledButton(onPressed: link.openNotifAccess, child: const Text('Buka')),
            ),
          )
        else
          Card(
            child: ListTile(
              leading: Icon(Icons.verified_outlined, color: cs.primary),
              title: const Text('Akses notifikasi aktif'),
              trailing: TextButton(onPressed: _test, child: const Text('Kirim uji')),
            ),
          ),
        if (!s.battery) ...[
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.battery_alert_outlined),
              title: const Text('Izinkan berjalan di latar'),
              subtitle: const Text('Supaya koneksi & notifikasi tidak dihentikan penghemat baterai.'),
              trailing: FilledButton.tonal(onPressed: link.openBattery, child: const Text('Atur')),
            ),
          ),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Teruskan notifikasi'),
          subtitle: const Text('Nama aplikasi, judul, dan potongan isi. Tidak disimpan di Lokana.'),
          value: s.enabled,
          onChanged: (v) async { await link.setNotifEnabled(v); _refresh(); },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Panggilan masuk'),
          subtitle: const Text('Nama penelepon tampil di Lokana (telepon & WhatsApp).'),
          value: s.calls,
          onChanged: (v) async { await link.setCallsEnabled(v); _refresh(); },
        ),
        const SizedBox(height: 16),
        Text('Aplikasi (${s.apps.length} dipilih)', style: t.titleMedium),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search), hintText: 'Cari aplikasi', border: OutlineInputBorder(), isDense: true),
          onChanged: (v) => setState(() => query = v),
        ),
        const SizedBox(height: 8),
        if (apps == null)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else
          for (final a in shown)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              enabled: s.enabled,
              secondary: a.icon != null
                  ? Image.memory(a.icon!, width: 36, height: 36, gaplessPlayback: true)
                  : const Icon(Icons.android, size: 36),
              title: Text(a.label),
              value: s.apps.contains(a.package),
              onChanged: (v) async { await link.setNotifApp(a.package, v == true); _refresh(); },
            ),
      ]),
    );
  }
}
