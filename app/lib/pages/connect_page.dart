import 'package:material_ui/material_ui.dart';
import '../link/link.dart';

/// Belum tersambung: scan Lokana di sekitar, sambungkan, pairing (kode 6 digit di OLED).
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final link = LokanaLink.instance;
  String? error;

  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    link.addListener(_changed);
  }

  @override
  void dispose() {
    link.removeListener(_changed);
    super.dispose();
  }

  Future<bool> _perms() async {
    if (await link.permissions()) return true;
    setState(() => error = 'Izin Bluetooth dibutuhkan untuk mencari Lokana.');
    return false;
  }

  Future<void> _scan() async {
    setState(() => error = null);
    if (!await _perms()) return;
    final e = await link.startScan();
    if (mounted) setState(() => error = e);
  }

  Future<void> _connect(String address, String name) async {
    setState(() => error = null);
    if (!await _perms()) return;
    final e = await link.connect(address, name);
    if (mounted) setState(() => error = e);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final busy = link.state == LinkState.connecting ||
        link.state == LinkState.pairing ||
        link.state == LinkState.reconnecting;
    final devices = link.found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));

    return Scaffold(
      appBar: AppBar(title: const Text('Lokana')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Sambungkan Lokana', style: t.headlineSmall),
        const SizedBox(height: 8),
        Text('Nyalakan Lokana dan dekatkan ke HP. HP baru akan diminta kode 6 digit '
            'yang tampil di layar Lokana.', style: t.bodyMedium),
        const SizedBox(height: 16),
        if (busy)
          Card(
            child: ListTile(
              leading: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
              title: Text(switch (link.state) {
                LinkState.pairing => 'Pairing dengan ${link.name ?? 'Lokana'}',
                LinkState.reconnecting => 'Menyambung ulang ke ${link.name ?? 'Lokana'}',
                _ => 'Menyambung ke ${link.name ?? 'Lokana'}',
              }),
              subtitle: link.message != null ? Text(link.message!) : null,
              trailing: TextButton(onPressed: () => link.disconnect(), child: const Text('Batal')),
            ),
          ),
        if (!busy && link.saved != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.history),
              title: Text(link.saved!.name),
              subtitle: const Text('Lokana terakhir'),
              trailing: FilledButton(
                onPressed: () => _connect(link.saved!.address, link.saved!.name),
                child: const Text('Sambungkan'),
              ),
              onLongPress: () => link.disconnect(forget: true),
            ),
          ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: TextStyle(color: cs.error)),
        ],
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: Text('Lokana di sekitar', style: t.titleMedium)),
          if (link.state == LinkState.scanning)
            TextButton.icon(onPressed: link.stopScan, icon: const Icon(Icons.stop), label: const Text('Berhenti'))
          else
            FilledButton.tonalIcon(
                onPressed: busy ? null : _scan, icon: const Icon(Icons.bluetooth_searching), label: const Text('Cari')),
        ]),
        if (link.state == LinkState.scanning) const LinearProgressIndicator(),
        const SizedBox(height: 8),
        if (devices.isEmpty && link.state != LinkState.scanning)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('Tekan "Cari" untuk mencari Lokana.', style: t.bodyMedium, textAlign: TextAlign.center),
          ),
        for (final d in devices)
          Card(
            child: ListTile(
              leading: const Icon(Icons.remove_red_eye_outlined),
              title: Text(d.name),
              subtitle: Text('Sinyal ${d.rssi} dBm'),
              trailing: const Icon(Icons.chevron_right),
              onTap: busy ? null : () => _connect(d.address, d.name),
            ),
          ),
      ]),
    );
  }
}
