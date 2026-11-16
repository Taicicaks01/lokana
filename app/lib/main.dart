// Aplikasi Lokana — pendamping robot mini Lokana.
// UI Flutter; koneksi BLE & Lokana Link di Kotlin (android/.../BleLink.kt).
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'link/link.dart';
import 'link/proto.dart';
import 'pages/connect_page.dart';
import 'pages/dashboard_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LokanaLink.instance.start();
  runApp(const LokanaApp());
}

const lokanaSeed = Color(0xFF2BB3C0);

class LokanaApp extends StatelessWidget {
  const LokanaApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: lokanaSeed, brightness: b),
          useMaterial3: true,
          cardTheme: const CardThemeData(margin: EdgeInsets.zero),
        );
    return MaterialApp(
      title: 'Lokana',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const HomePage(),
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
