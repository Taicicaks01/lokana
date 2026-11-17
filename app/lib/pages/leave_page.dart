import 'dart:async';
import 'package:material_ui/material_ui.dart';
import '../link/link.dart';
import '../link/proto.dart';
import '../main.dart';
import '../radar.dart';
import '../theme.dart';
import '../ui.dart';

/// Pengingat ketinggalan: HP berbunyi jika Lokana tertinggal (setelan di HP, dijalankan Kotlin LeaveAlert)
/// dan Lokana berbunyi jika HP tertinggal (SETTINGS leave_alert, firmware 0.5.4).
class LeavePage extends StatefulWidget {
  /// true = tampil di dalam tab (tanpa AppBar sendiri; judul dari tab).
  final bool embedded;
  const LeavePage({super.key, this.embedded = false});

  @override
  State<LeavePage> createState() => _LeavePageState();
}

class _LeavePageState extends State<LeavePage> {
  final link = LokanaLink.instance;
  final prefs = AppTheme.instance;
  late bool on = prefs.prefBool('leave_on', true);
  late int delay = prefs.prefInt('leave_delay', 20);
  late String mode = prefs.pref('leave_mode') ?? 'alarm';
  DateTime? snoozed;
  int? rssi;
  Timer? _rssiTimer;

  static const delays = {10: '10 dtk', 20: '20 dtk', 30: '30 dtk', 60: '1 mnt'};

  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    link.addListener(_changed);
    if (link.ready) link.send(T.settings, pSettingsGet());
    _loadSnooze();
    _pollRssi();
    _rssiTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) => _pollRssi());
  }

  Future<void> _pollRssi() async {
    final r = await link.rssi();
    if (mounted && r != rssi) setState(() => rssi = r);
  }

  @override
  void dispose() {
    link.removeListener(_changed);
    _rssiTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSnooze() async {
    final s = await link.leaveSnoozeUntil();
    if (mounted) setState(() => snoozed = s);
  }

  Future<void> _snooze(int minutes) async {
    await link.leaveSnooze(minutes);
    await _loadSnooze();
  }

  String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}.${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final s = link.ready ? link.settings : null;
    final lokanaOk = s?.leaveAlert != null;

    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Pengingat ketinggalan')),
      body: PageBody(children: [
        // ---------- Radar ----------
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          decoration: BoxDecoration(color: context.lk.hero, borderRadius: BorderRadius.circular(LokanaTokens.rHero)),
          child: Column(children: [
            LeaveRadar(rssi: link.ready ? rssi : null, size: 210),
            Text(radarLabel(link.ready ? rssi : null),
                style: t.titleMedium?.copyWith(color: Colors.white)),
            const SizedBox(height: Gap.xs),
            Text(
                rssi == null
                    ? 'Menunggu sinyal Lokana...'
                    : 'Cincin melebar & makin cepat saat Lokana menjauh. Kalau sambungan hilang, yang tertinggal '
                        'saling mengingatkan.',
                style: t.bodySmall?.copyWith(color: Colors.white70),
                textAlign: TextAlign.center),
          ]),
        ),

        // ---------- Di HP ----------
        const SectionHeader('Di HP ini', icon: Icons.smartphone_outlined, subtitle: 'Jika Lokana tertinggal'),
        Panel(children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('HP berbunyi jika Lokana tertinggal'),
            value: on,
            onChanged: (v) { setState(() => on = v); prefs.remember('leave_on', v); },
          ),
          if (on) ...[
            Field('Ingatkan setelah terputus',
                help: 'Memberi waktu Lokana tersambung lagi, misalnya saat lewat dinding tebal.',
                child: Choices<int>(
                  options: delays,
                  value: delay,
                  onChanged: (v) { setState(() => delay = v); prefs.remember('leave_delay', v); },
                )),
            Field('Cara mengingatkan',
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'alarm', icon: Icon(Icons.volume_up_outlined), label: Text('Bunyi alarm')),
                    ButtonSegment(value: 'notif', icon: Icon(Icons.vibration), label: Text('Getar saja')),
                  ],
                  selected: {mode},
                  onSelectionChanged: (v) { setState(() => mode = v.first); prefs.remember('leave_mode', v.first); },
                )),
            const SizedBox(height: Gap.l),
            if (snoozed != null)
              Notice('Dijeda sampai pukul ${_hhmm(snoozed!)}', icon: Icons.snooze,
                  action: TextButton(onPressed: () => _snooze(0), child: const Text('Lanjutkan')))
            else
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _snooze(60),
                    icon: const Icon(Icons.snooze),
                    label: const Text('Jeda 1 jam'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
                ),
                const SizedBox(width: Gap.s),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () async {
                      await link.leaveTest();
                      if (context.mounted) showSnack(context, 'Contoh pengingat 4 detik');
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Coba'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
                ),
              ]),
          ],
        ]),

        // ---------- Di Lokana ----------
        const SectionHeader('Di Lokana', icon: Icons.remove_red_eye_outlined, subtitle: 'Jika HP tertinggal'),
        Panel(children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Lokana berbunyi jika HP tertinggal'),
            subtitle: Text(!link.ready
                ? 'Sambungkan Lokana untuk mengatur'
                : s == null
                    ? 'Membaca pengaturan...'
                    : !lokanaOk
                        ? 'Perlu firmware Lokana 0.5.4'
                        : 'Bunyi 30 detik + layar "HP-mu tertinggal?". Tap Lokana untuk diam.'),
            value: s?.leaveAlert ?? false,
            onChanged: lokanaOk ? (v) => sendWithFeedback(context, T.settings, pSettingsSet(leaveAlert: v)) : null,
          ),
          const SizedBox(height: Gap.xs),
          FilledButton.tonalIcon(
            onPressed: lokanaOk
                ? () => sendWithFeedback(context, T.goto, pGoto('Tertinggal'), ok: 'Contoh pengingat di Lokana. Tap Lokana untuk diam.')
                : null,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Coba di Lokana'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ]),

        // ---------- Cara kerja ----------
        const SectionHeader('Cara kerjanya', icon: Icons.info_outline),
        Panel(children: [
          for (final tip in const [
            'Pengingat muncul jika sinyal Bluetooth melemah lalu hilang (berjauhan) dan tidak kembali dalam waktu tunggu.',
            'Memutus dari aplikasi tidak memicu pengingat. Lokana yang dimatikan di dekat HP hanya memberi notifikasi, tanpa bunyi.',
            'Jangkauan Bluetooth sekitar 10–30 m, lebih pendek jika terhalang tembok. Di rumah, pakai Jeda 1 jam.',
            'Pengingat di HP butuh aplikasi Lokana tetap berjalan di latar.',
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 6), child: Icon(Icons.circle, size: 6, color: cs.primary)),
                const SizedBox(width: Gap.s),
                Expanded(child: Text(tip, style: t.bodyMedium)),
              ]),
            ),
          const SizedBox(height: Gap.s),
          OutlinedButton.icon(
            onPressed: link.openBattery,
            icon: const Icon(Icons.battery_saver_outlined),
            label: const Text('Izinkan berjalan di latar'),
          ),
        ]),
      ]),
    );
  }
}
