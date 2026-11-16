import 'package:material_ui/material_ui.dart';
import '../link/link.dart';
import '../theme.dart';
import '../ui.dart';
import 'guide_page.dart';
import 'settings_page.dart';

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
      appBar: AppBar(title: const Text('Lokana'), actions: [
        IconButton(
          icon: const Icon(Icons.help_outline),
          tooltip: 'Cara pakai',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuidePage())),
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Pengaturan',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
        ),
      ]),
      body: PageBody(children: [
        // ---------- Pembuka ----------
        Card(
          color: Colors.black,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Colors.white12)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
            child: Column(children: [
              LokanaEyes(color: AppTheme.instance.oled.color, height: 54, sleepy: !busy),
              const SizedBox(height: Gap.l),
              Text(busy ? 'Menyambung...' : 'Sambungkan Lokana', style: t.headlineSmall?.copyWith(color: Colors.white)),
              const SizedBox(height: Gap.xs),
              Text('Nyalakan Lokana dan dekatkan ke HP. Saat pertama kali, masukkan kode 6 digit yang tampil di '
                  'layar Lokana.', style: t.bodySmall?.copyWith(color: Colors.white70), textAlign: TextAlign.center),
            ]),
          ),
        ),
        const SizedBox(height: Gap.m),
        if (busy)
          Panel(padding: const EdgeInsets.symmetric(vertical: 6), children: [
            ListTile(
              leading: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
              title: Text(switch (link.state) {
                LinkState.pairing => 'Pairing dengan ${link.name ?? 'Lokana'}',
                LinkState.reconnecting => 'Menyambung ulang ke ${link.name ?? 'Lokana'}',
                _ => 'Menyambung ke ${link.name ?? 'Lokana'}',
              }),
              subtitle: link.message != null ? Text(link.message!) : null,
              trailing: TextButton(onPressed: () => link.disconnect(), child: const Text('Batal')),
            ),
          ]),
        if (!busy && link.saved != null)
          Card(
            color: cs.primaryContainer,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onLongPress: () => link.disconnect(forget: true),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    IconBadge(Icons.history, background: cs.primary, color: cs.onPrimary),
                    const SizedBox(width: Gap.m),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(link.saved!.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: t.titleMedium?.copyWith(color: cs.onPrimaryContainer)),
                        Text('Lokana terakhir · tahan kartu ini untuk melupakan',
                            style: t.bodySmall?.copyWith(color: cs.onPrimaryContainer)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: Gap.m),
                  FilledButton.icon(
                    onPressed: () => _connect(link.saved!.address, link.saved!.name),
                    icon: const Icon(Icons.bluetooth_connected),
                    label: const Text('Sambungkan'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
                ]),
              ),
            ),
          ),
        if (link.action == 'bt_settings' && !busy) ...[
          const SizedBox(height: Gap.m),
          Panel(color: cs.errorContainer, children: [
            Text('Pairing lama perlu dihapus', style: t.titleSmall?.copyWith(color: cs.onErrorContainer)),
            const SizedBox(height: 4),
            Text(link.message ?? 'Lokana sudah melupakan HP ini. Hapus Lokana di Pengaturan Bluetooth HP, '
                'lalu sambungkan lagi untuk memasukkan kode baru.', style: TextStyle(color: cs.onErrorContainer)),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: link.openBluetoothSettings,
              icon: const Icon(Icons.bluetooth),
              label: const Text('Buka Pengaturan Bluetooth'),
            ),
          ]),
        ],
        if (error != null) ...[
          const SizedBox(height: Gap.m),
          Notice(error!, icon: Icons.error_outline, warning: true),
        ],

        // ---------- Lokana di sekitar ----------
        SectionHeader(
          'Lokana di sekitar',
          icon: Icons.bluetooth_searching,
          trailing: link.state == LinkState.scanning
              ? TextButton.icon(onPressed: link.stopScan, icon: const Icon(Icons.stop), label: const Text('Berhenti'))
              : FilledButton.tonalIcon(
                  onPressed: busy ? null : _scan, icon: const Icon(Icons.search), label: const Text('Cari')),
        ),
        if (link.state == LinkState.scanning)
          const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator()),
        if (devices.isEmpty && link.state != LinkState.scanning)
          Panel(children: [
            Icon(Icons.radar, size: 40, color: cs.outline),
            const SizedBox(height: Gap.s),
            Text('Tekan "Cari" untuk menemukan Lokana', style: t.bodyMedium, textAlign: TextAlign.center),
          ])
        else if (devices.isNotEmpty)
          Panel(padding: const EdgeInsets.symmetric(vertical: 6), children: [
            for (final d in devices)
              NavRow(
                icon: Icons.remove_red_eye_outlined,
                title: d.name,
                subtitle: 'Sinyal ${d.rssi > -60 ? 'kuat' : d.rssi > -80 ? 'sedang' : 'lemah'} (${d.rssi} dBm)',
                onTap: busy ? null : () => _connect(d.address, d.name),
              ),
          ]),
      ]),
    );
  }
}
