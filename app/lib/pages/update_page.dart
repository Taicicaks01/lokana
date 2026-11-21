import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import '../cube.dart';
import '../link/link.dart';
import '../link/proto.dart';
import '../main.dart';
import '../theme.dart';
import '../ui.dart';

/// Rilis Lokana OS di GitHub Releases (aset firmware bernama `lokana-os-<versi>.bin`).
class _Release {
  final String tag, name, url, notes, assetUrl;
  final int assetSize;
  final DateTime? date;
  _Release(this.tag, this.name, this.url, this.notes, this.assetUrl, this.assetSize, this.date);
  String get version => tag.startsWith('v') ? tag.substring(1) : tag;
}

enum _Phase { idle, sending, restarting, verifying, success, rolledBack, failed }

/// Pembaruan firmware lewat aplikasi (OTA, LOKANA_LINK.md §OTA): dari GitHub Releases atau file .bin di HP.
/// Setelah terkirim Lokana restart; firmware baru diuji ±10 dtk, kalau gagal Lokana kembali ke versi lama.
class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});

  static const repo = 'Taicicaks01/lokana';

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  final link = LokanaLink.instance;
  _Release? release;
  String? releaseMsg;
  bool checking = false;
  ({String name, Uint8List bytes, String? version})? file;

  _Phase phase = _Phase.idle;
  double progress = 0;
  String? error, target, before;
  DateTime? sendStart;
  Timer? _timeout, _verify;
  bool _sawDrop = false;
  int _infoAtDrop = 0;      // link.infoCount saat koneksi putus; versi dinilai dari DEVICE_INFO sesudahnya

  @override
  void initState() {
    super.initState();
    link.addListener(_onLink);
  }

  @override
  void dispose() {
    link.removeListener(_onLink);
    _timeout?.cancel();
    _verify?.cancel();
    if (phase == _Phase.sending) link.cancelOta();
    link.keepScreenOn(false);
    super.dispose();
  }

  String get _current => link.info?.fwVersion ?? '?';

  // ---------- Setelah END: tunggu Lokana restart & tersambung lagi ----------
  void _onLink() {
    if (!mounted) return;
    if (phase == _Phase.restarting || phase == _Phase.verifying) {
      if (!link.ready) {
        _infoAtDrop = link.infoCount;                   // tidak ada frame selama putus: angka ini tetap
        _sawDrop = true;
        if (phase == _Phase.verifying) { _verify?.cancel(); phase = _Phase.restarting; }   // restart lagi di masa uji
      } else if (_sawDrop && link.info != null && link.infoCount > _infoAtDrop) {
        // Hanya DEVICE_INFO baru (sesudah restart): `info` lama masih berisi versi sebelum pembaruan
        final v = link.info!.fwVersion;
        if (v == target && phase == _Phase.restarting) {
          // Firmware baru menyala; tunggu masa uji (±10 dtk) sebelum dinyatakan berhasil
          phase = _Phase.verifying;
          _verify = Timer(const Duration(seconds: 12), () => _finish(_Phase.success));
        } else if (v != target) {
          _finish(_Phase.rolledBack);
        }
      }
    }
    setState(() {});
  }

  void _finish(_Phase p, [String? msg]) {
    _timeout?.cancel();
    _verify?.cancel();
    link.keepScreenOn(false);
    sendReaction(p == _Phase.success);
    if (mounted) setState(() { phase = p; error = msg; });
  }

  // ---------- Sumber firmware ----------
  Future<void> _check() async {
    setState(() { checking = true; releaseMsg = null; });
    try {
      final c = HttpClient()..userAgent = 'Lokana-App/$appVersion';
      final req = await c.getUrl(Uri.parse('https://api.github.com/repos/${UpdatePage.repo}/releases/latest'))
          .timeout(const Duration(seconds: 15));
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      c.close();
      if (res.statusCode == 404) { setState(() { release = null; releaseMsg = 'Belum ada rilis Lokana OS di GitHub.'; }); return; }
      if (res.statusCode != 200) { setState(() => releaseMsg = 'GitHub membalas ${res.statusCode}. Coba lagi nanti.'); return; }
      final j = jsonDecode(body) as Map<String, dynamic>;
      final assets = (j['assets'] as List? ?? const []).cast<Map<String, dynamic>>();
      final a = assets.where((x) => RegExp(r'^lokana-os-.*\.bin$').hasMatch(x['name'] as String? ?? '')).firstOrNull;
      if (a == null) {
        setState(() => releaseMsg = 'Rilis terbaru (${j['tag_name']}) belum berisi file firmware lokana-os-*.bin.');
        return;
      }
      setState(() => release = _Release(
            j['tag_name'] as String? ?? '?',
            j['name'] as String? ?? '',
            j['html_url'] as String? ?? 'https://github.com/${UpdatePage.repo}/releases',
            j['body'] as String? ?? '',
            a['browser_download_url'] as String,
            a['size'] as int? ?? 0,
            DateTime.tryParse(j['published_at'] as String? ?? ''),
          ));
    } catch (e) {
      setState(() => releaseMsg = 'Tidak bisa menghubungi GitHub. Periksa internet HP.');
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> _installRelease(_Release r) async {
    setState(() { phase = _Phase.sending; progress = 0; error = null; target = r.version; });
    try {
      final c = HttpClient()..userAgent = 'Lokana-App/$appVersion';
      final res = await (await c.getUrl(Uri.parse(r.assetUrl))).close();
      final b = BytesBuilder(copy: false);
      await for (final part in res) { b.add(part); }
      c.close();
      final bin = b.takeBytes();
      if (res.statusCode != 200 || firmwareVersion(bin) == null) {
        _finish(_Phase.failed, 'File rilis tidak bisa diunduh atau bukan firmware Lokana.');
        return;
      }
      await _install(bin, firmwareVersion(bin)!);
    } catch (_) {
      _finish(_Phase.failed, 'Unduhan gagal. Periksa internet HP.');
    }
  }

  Future<void> _pick() async {
    final f = await link.pickFile();
    if (f == null) return;
    setState(() => file = (name: f.name, bytes: f.bytes, version: firmwareVersion(f.bytes)));
  }

  Future<void> _install(Uint8List bin, String version) async {
    before = _current;
    target = version;
    _sawDrop = false;
    setState(() { phase = _Phase.sending; progress = 0; error = null; sendStart = DateTime.now(); });
    await link.keepScreenOn(true);
    final err = await link.sendFirmware(bin, version, onProgress: (p) {
      if (mounted) setState(() => progress = p);
    });
    if (err != null) { _finish(_Phase.failed, err); return; }
    setState(() => phase = _Phase.restarting);
    _timeout = Timer(const Duration(seconds: 90), () {
      if (phase == _Phase.restarting) {
        _finish(_Phase.failed, 'Lokana belum tersambung lagi. Pastikan Lokana menyala dan dekat dengan HP.');
      }
    });
  }

  Future<bool> _confirm(String version) async {
    final newer = versionAtLeast(version, _current) && version != _current;
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('Pasang Lokana OS $version?'),
            content: Text([
              if (!newer) 'Versi ini tidak lebih baru dari yang terpasang ($_current).',
              'Proses ±1–2 menit. Biarkan aplikasi terbuka dan Lokana dekat dengan HP. Kalau versi baru gagal '
                  'menyala, Lokana otomatis kembali ke versi sekarang.',
            ].join('\n\n')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Pasang')),
            ],
          ),
        ) ??
        false;
  }

  // ---------- Tampilan ----------
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final lk = context.lk;
    final busy = phase == _Phase.sending || phase == _Phase.restarting || phase == _Phase.verifying;
    final mood = switch (phase) {
      _Phase.sending => CubeMood.mencari,
      _Phase.restarting => CubeMood.mengantuk,
      _Phase.success => CubeMood.senang,
      _ => link.ready ? CubeMood.idle : CubeMood.mengantuk,
    };

    return PopScope(
      canPop: !busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) showSnack(context, 'Tunggu sampai pembaruan selesai');
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Pembaruan firmware'), automaticallyImplyLeading: !busy),
        body: PageBody(children: [
          // ---------- Hero ----------
          Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            decoration: BoxDecoration(color: lk.hero, borderRadius: BorderRadius.circular(LokanaTokens.rHero)),
            child: Column(children: [
              LokanaCube(scale: 0.7, mood: mood),
              const SizedBox(height: Gap.m),
              Text('Lokana OS $_current', style: t.titleLarge?.copyWith(color: Colors.white)),
              const SizedBox(height: Gap.xs),
              Text(
                  link.ready ? 'Versi yang sedang berjalan di Lokana' : 'Lokana belum tersambung',
                  style: t.bodySmall?.copyWith(color: Colors.white70)),
            ]),
          ),
          const SizedBox(height: Gap.m),

          if (link.ready && !link.hasOta)
            const Notice(
                'Lokana OS ini belum bisa diperbarui lewat aplikasi. Perbarui sekali lewat kabel USB '
                '(firmware 0.5.5 ke atas), setelah itu pembaruan berikutnya bisa dari sini.',
                icon: Icons.usb, warning: true),

          // ---------- Proses ----------
          if (phase != _Phase.idle) _status(t, lk),

          if (!busy && link.ready && link.hasOta) ...[
            // ---------- GitHub ----------
            SectionHeader('Rilis resmi', icon: Icons.cloud_download_outlined,
                subtitle: 'Dari GitHub Releases ${UpdatePage.repo}'),
            Panel(children: [
              if (release == null) ...[
                if (releaseMsg != null) ...[Text(releaseMsg!, style: t.bodyMedium), const SizedBox(height: Gap.m)],
                FilledButton.tonalIcon(
                  onPressed: checking ? null : _check,
                  icon: const Icon(Icons.refresh),
                  label: Text(checking ? 'Memeriksa...' : 'Cek pembaruan'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ] else
                _releaseCard(release!, t, lk),
              const SizedBox(height: Gap.xs),
              TextButton.icon(
                onPressed: () => link.openUrl(release?.url ?? 'https://github.com/${UpdatePage.repo}/releases'),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Lihat perubahan & kode di GitHub'),
              ),
            ]),

            // ---------- File ----------
            const SectionHeader('Dari file', icon: Icons.folder_open_outlined, subtitle: 'Firmware .bin di HP ini'),
            Panel(children: [
              if (file != null) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const IconBadge(Icons.memory, size: 40),
                  title: Text(file!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${(file!.bytes.length / 1024).toStringAsFixed(0)} KB · '
                      '${file!.version == null ? 'bukan firmware Lokana' : 'Lokana OS ${file!.version}'}'),
                ),
                if (file!.version == null)
                  const Notice('File ini bukan firmware Lokana (tidak ada penanda versi Lokana OS). Lokana menolak '
                      'file seperti ini.', icon: Icons.error_outline, warning: true)
                else
                  FilledButton.icon(
                    onPressed: () async {
                      if (await _confirm(file!.version!)) await _install(file!.bytes, file!.version!);
                    },
                    icon: const Icon(Icons.system_update_alt),
                    label: Text('Pasang Lokana OS ${file!.version}'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52))
                        .merge(AppTheme.primaryButton(context)),
                  ),
                const SizedBox(height: Gap.s),
              ],
              OutlinedButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.file_open_outlined),
                label: Text(file == null ? 'Pilih file .bin' : 'Pilih file lain'),
              ),
              const SizedBox(height: Gap.s),
              Text('Untuk pengembang: hasil build PlatformIO ada di firmware/.pio/build/supermini/firmware.bin.',
                  style: t.bodySmall),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _releaseCard(_Release r, TextTheme t, LokanaTokens lk) {
    final newer = versionAtLeast(r.version, _current) && r.version != _current;
    final notes = r.notes.split('\n').where((l) => l.trim().isNotEmpty).take(6).join('\n');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(r.name.isEmpty ? 'Lokana OS ${r.version}' : r.name, style: t.titleMedium)),
        Pill(newer ? 'Baru' : 'Terpasang', color: newer ? lk.pinkText : lk.muted),
      ]),
      Text([
        if (r.date != null) '${r.date!.day}/${r.date!.month}/${r.date!.year}',
        '${(r.assetSize / 1024).toStringAsFixed(0)} KB',
      ].join(' · '), style: t.bodySmall),
      if (notes.isNotEmpty) ...[
        const SizedBox(height: Gap.s),
        Text(notes, style: t.bodyMedium, maxLines: 6, overflow: TextOverflow.ellipsis),
      ],
      const SizedBox(height: Gap.m),
      if (newer)
        FilledButton.icon(
          onPressed: () async { if (await _confirm(r.version)) await _installRelease(r); },
          icon: const Icon(Icons.system_update_alt),
          label: Text('Pasang Lokana OS ${r.version}'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)).merge(AppTheme.primaryButton(context)),
        )
      else
        const Notice('Lokana sudah memakai versi terbaru.', icon: Icons.check_circle_outline),
    ]);
  }

  Widget _status(TextTheme t, LokanaTokens lk) {
    switch (phase) {
      case _Phase.sending:
        final secs = sendStart == null ? 0.0 : DateTime.now().difference(sendStart!).inMilliseconds / 1000;
        final eta = progress > 0.02 ? (secs / progress - secs).round() : null;
        return Panel(children: [
          Text('Mengirim Lokana OS $target', style: t.titleMedium),
          const SizedBox(height: Gap.m),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: progress, minHeight: 10),
          ),
          const SizedBox(height: Gap.s),
          Text('${(progress * 100).floor()}%${eta == null ? '' : ' · sisa ±$eta dtk'}', style: t.bodyMedium),
          const SizedBox(height: Gap.s),
          Text('Biarkan aplikasi terbuka dan Lokana dekat dengan HP. Lokana tetap memakai versi lama sampai '
              'semua data diterima dan diperiksa.', style: t.bodySmall),
          const SizedBox(height: Gap.s),
          OutlinedButton(onPressed: link.cancelOta, child: const Text('Batalkan')),
        ]);
      case _Phase.restarting:
      case _Phase.verifying:
        return Panel(children: [
          Text(phase == _Phase.restarting ? 'Lokana memasang & menyalakan ulang...' : 'Menguji Lokana OS $target...',
              style: t.titleMedium),
          const SizedBox(height: Gap.m),
          const LinearProgressIndicator(minHeight: 4),
          const SizedBox(height: Gap.s),
          Text(phase == _Phase.restarting
              ? 'Layar Lokana menampilkan "Memasang ulang". HP akan tersambung lagi sendiri.'
              : 'Versi baru sudah menyala. Lokana memastikannya berjalan sehat selama ±10 detik.',
              style: t.bodySmall),
        ]);
      case _Phase.success:
        return Notice('Berhasil! Lokana sekarang memakai Lokana OS $target.', icon: Icons.check_circle_outline);
      case _Phase.rolledBack:
        return Notice('Lokana OS $target gagal menyala, jadi Lokana kembali ke versi sebelumnya ($_current). '
            'Lokana tetap aman dipakai.', icon: Icons.history, warning: true);
      case _Phase.failed:
        return Notice('Pembaruan gagal: ${error ?? '?'}. Lokana tetap memakai versi sebelumnya.',
            icon: Icons.error_outline, warning: true);
      case _Phase.idle:
        return const SizedBox.shrink();
    }
  }
}
