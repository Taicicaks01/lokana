// Aplikasi Lokana — pendamping robot mini Lokana.
// UI Flutter; koneksi BLE & Lokana Link di Kotlin (android/.../BleLink.kt).
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'link/link.dart';
import 'link/proto.dart';
import 'pages/connect_page.dart';
import 'pages/dashboard_page.dart';
import 'splash.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Baloo 2'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  LokanaLink.instance.start();
  await AppTheme.instance.load();      // perlu tahu warna & setelan animasi pembuka sebelum frame pertama
  runApp(const LokanaApp());
}

class LokanaApp extends StatefulWidget {
  const LokanaApp({super.key});

  @override
  State<LokanaApp> createState() => _LokanaAppState();
}

class _LokanaAppState extends State<LokanaApp> {
  late bool _splash = AppTheme.instance.splash;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.instance;
    return ListenableBuilder(
      listenable: t,
      builder: (context, _) => MaterialApp(
        title: 'Lokana',
        debugShowCheckedModeBanner: false,
        theme: t.data(Brightness.light),
        darkTheme: t.data(Brightness.dark),
        themeMode: t.mode,
        home: AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          child: _splash
              ? LokanaSplash(key: const ValueKey('splash'), onDone: () => setState(() => _splash = false))
              : const HomePage(),
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final link = LokanaLink.instance;
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) => Stack(children: [
        link.ready ? const DashboardPage() : const ConnectPage(),
        if (link.phoneRinging) const _FindPhoneOverlay(),
      ]),
    );
  }
}

/// Lokana sedang memanggil HP ini (FIND_PHONE). Bunyi dari sisi Kotlin; di sini tombol "Ketemu".
class _FindPhoneOverlay extends StatelessWidget {
  const _FindPhoneOverlay();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer,
      child: SafeArea(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.phonelink_ring, size: 96, color: cs.onPrimaryContainer),
            const SizedBox(height: 24),
            Text('Lokana memanggil HP ini', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => LokanaLink.instance.phoneFound(),
              icon: const Icon(Icons.check),
              label: const Text('Ketemu!'),
              style: FilledButton.styleFrom(minimumSize: const Size(200, 56)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Kirim pesan lalu tampilkan hasilnya singkat di bawah layar.
Future<bool> sendWithFeedback(BuildContext context, int type, Uint8List payload, {String? ok}) async {
  final st = await LokanaLink.instance.send(type, payload);
  if (!context.mounted) return st == Status.ok;
  final msg = st == Status.ok ? ok : Status.describe(st);
  if (msg != null) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }
  return st == Status.ok;
}
