import 'package:material_ui/material_ui.dart';

import '../link/link.dart';
import '../link/proto.dart';
import '../main.dart';
import '../ui.dart';

/// Penerusan notifikasi & panggilan ke Lokana. Hanya aplikasi yang dicentang yang diteruskan.
class NotifPage extends StatefulWidget {
  /// true = tampil di dalam tab (tanpa AppBar sendiri; judul dari tab).
  final bool embedded;
  const NotifPage({super.key, this.embedded = false});

  @override
  State<NotifPage> createState() => _NotifPageState();
}

class _NotifPageState extends State<NotifPage> with WidgetsBindingObserver {
  final link = LokanaLink.instance;
  NotifStatus? status;
  List<AppEntry>? apps;
  String query = '';

  static const popupChoices = {0: 'Jangan muncul', 3: '3 dtk', 6: '6 dtk', 10: '10 dtk', 15: '15 dtk', 30: '30 dtk'};

  void _onLink() {
    if (mounted) setState(() {});
  } // REPORT pengaturan dari Lokana

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    link.addListener(_onLink);
    _refresh();
    link.installedApps().then((a) => mounted ? setState(() => apps = a) : null);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    link.removeListener(_onLink);
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(st == Status.ok ? 'Notifikasi uji terkirim ke Lokana' : Status.describe(st))),
    );
  }

  String _popupHelp() {
    if (!link.ready) return 'Sambungkan Lokana untuk mengatur.';
    final v = link.settings?.notifPopupS;
    if (v == null) return 'Perlu firmware Lokana 0.5.2 atau lebih baru.';
    if (v == 0) return 'Notifikasi hanya berbunyi dan masuk modul Notif di Lokana.';
    return 'Notifikasi baru tampil $v detik (penting +4 detik), lalu Lokana kembali ke layar sebelumnya.';
  }

  @override
  Widget build(BuildContext context) {
    final s = status;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    if (s == null) {
      return Scaffold(
        appBar: widget.embedded ? null : AppBar(title: const Text('Notifikasi')),
        body: const PageBody(children: [SkeletonCard(height: 64), SizedBox(height: 12), SkeletonCard(height: 150),
            SizedBox(height: 12), SkeletonCard(height: 120)]),
      );
    }
    final q = query.toLowerCase();
    final shown =
        (apps ?? const <AppEntry>[])
            .where((a) => q.isEmpty || a.label.toLowerCase().contains(q) || a.package.contains(q))
            .toList()
          ..sort((a, b) {
            final sa = s.apps.contains(a.package), sb = s.apps.contains(b.package);
            return sa == sb ? a.label.toLowerCase().compareTo(b.label.toLowerCase()) : (sa ? -1 : 1);
          });

    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Notifikasi')),
      body: PageBody(
        children: [
          if (!s.access)
            Card(
              color: cs.errorContainer,
              child: ListTile(
                leading: Icon(Icons.notifications_off_outlined, color: cs.onErrorContainer),
                title: Text('Izinkan akses notifikasi', style: TextStyle(color: cs.onErrorContainer)),
                subtitle: Text(
                  'Aktifkan "Lokana" di daftar akses notifikasi Android.',
                  style: TextStyle(color: cs.onErrorContainer),
                ),
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
          const SectionHeader('Penerusan', icon: Icons.forward_to_inbox_outlined),
          Panel(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Teruskan notifikasi'),
                subtitle: const Text('Nama aplikasi, judul, dan potongan isi. Tidak disimpan di Lokana.'),
                value: s.enabled,
                onChanged: (v) async {
                  await link.setNotifEnabled(v);
                  _refresh();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Panggilan masuk'),
                subtitle: const Text('Nama penelepon tampil di Lokana (telepon & WhatsApp).'),
                value: s.calls,
                onChanged: (v) async {
                  await link.setCallsEnabled(v);
                  _refresh();
                },
              ),
            ],
          ),
          const SectionHeader('Lama tampil di Lokana', icon: Icons.timer_outlined),
          Panel(
            children: [
              Text(_popupHelp(), style: t.bodySmall),
              const SizedBox(height: Gap.s),
              Choices<int>(
                options: popupChoices,
                value: link.settings?.notifPopupS,
                onChanged: link.ready && link.settings?.notifPopupS != null
                    ? (v) => sendWithFeedback(context, T.settings, pSettingsSet(notifPopupS: v))
                    : null,
              ),
            ],
          ),
          SectionHeader(
            'Aplikasi',
            icon: Icons.apps_outlined,
            subtitle: '${s.apps.length} dipilih · yang dipilih di atas',
          ),
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cari aplikasi', isDense: true),
            onChanged: (v) => setState(() => query = v),
          ),
          const SizedBox(height: 8),
          if (apps == null)
            for (var i = 0; i < 4; i++) const Padding(padding: EdgeInsets.only(bottom: 8), child: SkeletonCard(height: 52))
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
                onChanged: (v) async {
                  await link.setNotifApp(a.package, v == true);
                  _refresh();
                },
              ),
        ],
      ),
    );
  }
}
