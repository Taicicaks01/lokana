// Jembatan ke sisi Kotlin (BleLink): state koneksi, hasil scan, frame dari Lokana.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'proto.dart';

enum LinkState { idle, scanning, connecting, pairing, ready, reconnecting }

class FoundDevice {
  final String address, name;
  int rssi;
  FoundDevice(this.address, this.name, this.rssi);
}

class LokanaLink extends ChangeNotifier {
  LokanaLink._();
  static final instance = LokanaLink._();

  static const _m = MethodChannel('lokana/link');
  static const _e = EventChannel('lokana/events');

  LinkState state = LinkState.idle;
  String? address, name, message;
  /// Saran tindakan dari sisi Kotlin: 'bt_settings' = hapus pairing di Pengaturan Bluetooth HP.
  String? action;
  /// Lokana sedang berbunyi (cari kunci), dilaporkan Lokana sendiri sejak firmware 0.5.0.
  bool findingKeys = false;
  Timer? _findFallback;
  int mtu = 23;
  ({String address, String name})? saved;
  DeviceInfo? info;
  /// Bertambah tiap DEVICE_INFO diterima dari Lokana. `info` tidak dikosongkan saat putus, jadi layar yang
  /// butuh versi terbaru setelah restart (Update) menunggu angka ini naik.
  int infoCount = 0;
  LokanaSettings? settings;
  final found = <String, FoundDevice>{};
  final dice = <DiceResult>[];
  bool phoneRinging = false;

  /// Frame mentah dari Lokana (selain ACK) untuk layar yang butuh.
  final _frames = StreamController<(int, Uint8List)>.broadcast();
  Stream<(int, Uint8List)> get frames => _frames.stream;

  StreamSubscription? _sub;

  Future<void> start() async {
    _sub ??= _e.receiveBroadcastStream().listen(_onEvent);
    await refresh();
  }

  Future<void> refresh() async {
    final s = await _m.invokeMapMethod<String, dynamic>('snapshot');
    if (s == null) return;
    _setState(s['state'] as String?);
    address = s['address'] as String?;
    name = s['name'] as String?;
    mtu = s['mtu'] as int? ?? mtu;
    final sv = s['saved'] as Map?;
    saved = sv == null ? null : (address: sv['address'] as String, name: sv['name'] as String);
    final di = s['deviceInfo'] as Uint8List?;
    if (di != null) info = DeviceInfo.parse(di);
    final st = s['settings'] as Uint8List?;
    if (st != null) settings = LokanaSettings.parse(st);
    phoneRinging = s['ringing'] == true;
    action = s['action'] as String?;
    notifyListeners();
  }

  void _setState(String? id) {
    state = LinkState.values.firstWhere((v) => v.name == id, orElse: () => LinkState.idle);
  }

  void _onEvent(dynamic ev) {
    final e = ev as Map;
    switch (e['event']) {
      case 'state':
        _setState(e['state'] as String?);
        address = e['address'] as String? ?? address;
        name = e['name'] as String? ?? name;
        message = e['message'] as String?;
        action = e['action'] as String?;
        mtu = e['mtu'] as int? ?? mtu;
        if (state == LinkState.ready && address != null) saved = (address: address!, name: name ?? 'Lokana');
        if (state == LinkState.idle) phoneRinging = false;
        if (state != LinkState.ready) findingKeys = false;
      case 'scan':
        final a = e['address'] as String;
        found.update(a, (d) => d..rssi = e['rssi'] as int,
            ifAbsent: () => FoundDevice(a, e['name'] as String, e['rssi'] as int));
      case 'frame':
        _onFrame(e['type'] as int, e['payload'] as Uint8List);
    }
    notifyListeners();
  }

  void _onFrame(int type, Uint8List p) {
    switch (type) {
      case T.deviceInfo:
        info = DeviceInfo.parse(p);
        infoCount++;
      case T.settings:
        settings = LokanaSettings.parse(p);
      case T.dice:
        final r = DiceResult.parse(p);
        if (r != null) {
          dice.insert(0, r);
          if (dice.length > 20) dice.removeLast();
        }
      case T.findPhone:
        phoneRinging = p.isNotEmpty && p[0] != 0;
      case T.findKeys:
        setFindingKeys(p.isNotEmpty && p[0] != 0, seconds: p.length > 1 ? p[1] : 30);
    }
    _frames.add((type, p));
  }

  // ---------------- Perintah ----------------
  Future<bool> permissions() async => await _m.invokeMethod<bool>('permissions') ?? false;

  /// null = berhasil, selain itu pesan kesalahan untuk pengguna.
  Future<String?> startScan() async {
    found.clear();
    notifyListeners();
    return _m.invokeMethod<String>('startScan');
  }

  Future<void> stopScan() => _m.invokeMethod('stopScan');

  Future<String?> connect(String address, String name) =>
      _m.invokeMethod<String>('connect', {'address': address, 'name': name});

  Future<void> disconnect({bool forget = false}) async {
    await _m.invokeMethod('disconnect', {'forget': forget});
    if (forget) saved = null;
    info = null;
    settings = null;
    notifyListeners();
  }

  /// Kirim pesan. Hasil: status ACK (lihat [Status]).
  Future<int> send(int type, Uint8List payload, {bool ack = true}) async =>
      await _m.invokeMethod<int>('send', {'type': type, 'payload': payload, 'ack': ack}) ?? Status.noAck;

  Future<void> phoneFound() async {
    phoneRinging = false;
    notifyListeners();
    await _m.invokeMethod('phoneFound');
  }

  bool get ready => state == LinkState.ready;

  /// Status tombol cari kunci. Cadangan timer untuk firmware lama yang belum melapor.
  void setFindingKeys(bool on, {int seconds = 30}) {
    findingKeys = on;
    _findFallback?.cancel();
    if (on) {
      _findFallback = Timer(Duration(seconds: seconds + 2), () {
        findingKeys = false;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  /// Lupakan Lokana ini di HP dan di Lokana. true = keduanya berhasil.
  Future<bool> forget() async {
    final ok = await _m.invokeMethod<bool>('forget') ?? false;
    saved = null;
    info = null;
    settings = null;
    notifyListeners();
    return ok;
  }

  Future<void> openBluetoothSettings() => _m.invokeMethod('openBluetooth');

  // ---------------- Nada Cari HP (0.5.2) ----------------
  /// Nama nada yang dipakai saat Lokana memanggil HP ini.
  Future<String> ringtoneTitle() async =>
      (await _m.invokeMapMethod<String, dynamic>('ringtoneInfo'))?['title'] as String? ?? 'Bawaan (alarm HP)';
  /// Pilih dari nada sistem ([file] = false) atau file audio sendiri. Hasil: nama nada baru, null = batal.
  Future<String?> pickRingtone({bool file = false}) =>
      _m.invokeMethod<String>(file ? 'pickRingtoneFile' : 'pickRingtone');
  Future<String?> resetRingtone() => _m.invokeMethod<String>('resetRingtone');
  Future<void> previewRingtone() => _m.invokeMethod('previewRingtone');
  Future<void> stopRingtonePreview() => _m.invokeMethod('stopPreview');

  /// Kekuatan sinyal Lokana (dBm) yang diukur HP tiap 2,5 dtk. null = belum ada / tidak tersambung.
  Future<int?> rssi() async {
    try { return await _m.invokeMethod<int>('rssi'); } catch (_) { return null; }
  }

  // ---------------- Pengingat ketinggalan (0.5.4) ----------------
  /// Contoh pengingat di HP ini selama 4 detik.
  Future<void> leaveTest() => _m.invokeMethod('leaveTest');
  /// Jeda pengingat [minutes] menit; 0 = lanjutkan.
  Future<void> leaveSnooze(int minutes) => _m.invokeMethod('leaveSnooze', {'minutes': minutes});
  /// Pengingat dijeda sampai kapan (null = tidak dijeda).
  Future<DateTime?> leaveSnoozeUntil() async {
    final ms = (await _m.invokeMapMethod<String, dynamic>('leaveInfo'))?['snoozeUntil'] as int? ?? 0;
    return ms > DateTime.now().millisecondsSinceEpoch ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  /// Simpan PNG ke galeri HP (Pictures/Lokana).
  Future<bool> saveImage(Uint8List png, String name) async =>
      await _m.invokeMethod<bool>('saveImage', {'bytes': png, 'name': name}) ?? false;

  /// Pilih gambar / GIF dari HP. null = batal.
  Future<Uint8List?> pickImage() => _m.invokeMethod<Uint8List>('pickImage');

  // ---------------- Galeri gambar (ANIM) ----------------
  bool get hasAnim => info?.has(Caps.anim) ?? false;

  /// Kirim animasi: BEGIN, setiap bingkai (dengan ACK), END. [onProgress] 0..1.
  Future<int> sendAnim(Anim1 a, {int slot = 0, int durationS = 0, void Function(double)? onProgress}) async {
    var st = await send(T.anim, pAnimBegin(a, slot: slot, durationS: durationS));
    if (st != Status.ok) return st;
    for (var i = 0; i < a.frames.length; i++) {
      st = await send(T.anim, pAnimFrame(i, a.frames[i]));
      if (st != Status.ok) {
        await send(T.anim, pAnimOp(AnimOp.abort), ack: false);
        return st;
      }
      onProgress?.call((i + 1) / a.frames.length);
    }
    return send(T.anim, pAnimOp(AnimOp.end));
  }

  /// Isi slot 1-8: (bingkai, w, h); bingkai 0 = kosong. null = tidak ada balasan.
  Future<List<(int, int, int)>?> listSlots() async {
    final reply = frames
        .where((f) => f.$1 == T.anim && f.$2.isNotEmpty && f.$2[0] == AnimOp.listReport)
        .first
        .timeout(const Duration(seconds: 3))
        .then<Uint8List?>((f) => f.$2, onError: (_) => null);
    final st = await send(T.anim, pAnimOp(AnimOp.list));
    if (st != Status.ok) return null;
    final p = await reply;
    return p == null ? null : parseAnimList(p);
  }

  /// Baca isi slot dari Lokana (bingkai pertama saja untuk thumbnail).
  Future<Anim1?> readSlot(int slot, {bool firstOnly = false}) async {
    final asm = AnimAssembler();
    final done = Completer<Anim1?>();
    final sub = frames.where((f) => f.$1 == T.anim).listen((f) {
      final a = asm.feed(f.$2);
      if (a != null && !done.isCompleted) done.complete(a);
    });
    try {
      final st = await send(T.anim, pAnimOp(AnimOp.read, [slot, firstOnly ? 1 : 0]));
      if (st != Status.ok) return null;
      return await done.future.timeout(const Duration(seconds: 10), onTimeout: () => null);
    } finally {
      await sub.cancel();
    }
  }

  Future<int> deleteSlot(int slot) => send(T.anim, pAnimOp(AnimOp.delete, [slot]));
  Future<int> showSlot(int slot, {int durationS = 0}) => send(T.anim, pAnimShow(slot, durationS: durationS));

  // ---------------- Pembaruan firmware (OTA, firmware 0.5.5) ----------------
  bool get hasOta => info?.has(Caps.ota) ?? false;

  Future<Uint8List> sha256(Uint8List bytes) async =>
      await _m.invokeMethod<Uint8List>('sha256', {'bytes': bytes}) ?? Uint8List(0);
  /// Pilih file firmware dari HP. null = batal / terlalu besar.
  Future<({String name, Uint8List bytes})?> pickFile() async {
    final m = await _m.invokeMapMethod<String, dynamic>('pickFile');
    if (m == null) return null;
    return (name: m['name'] as String, bytes: m['bytes'] as Uint8List);
  }
  Future<bool> openUrl(String url) async => await _m.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
  Future<void> keepScreenOn(bool on) => _m.invokeMethod('keepScreenOn', {'on': on});

  bool _otaCancel = false;
  void cancelOta() => _otaCancel = true;

  /// Kirim firmware: BEGIN, CHUNK berurutan (masing-masing ber-ACK), END. [onProgress] 0..1.
  /// Hasil: null = terpasang (Lokana restart), selain itu pesan kesalahan untuk pengguna.
  Future<String?> sendFirmware(Uint8List bin, String version, {void Function(double)? onProgress}) async {
    _otaCancel = false;
    final hash = await sha256(bin);
    int? abortReason;
    final sub = frames.where((f) => f.$1 == T.ota && f.$2.length >= 2 && f.$2[0] == OtaOp.abort)
        .listen((f) => abortReason = f.$2[1]);
    String? fail(int st) => abortReason != null ? otaReason(abortReason!) : Status.describe(st);
    await _m.invokeMethod('otaPriority', {'on': true});    // interval koneksi pendek selama kirim
    try {
      var st = await send(T.ota, pOtaBegin(bin.length, hash, version));
      if (st != Status.ok) return fail(st);
      for (var off = 0; off < bin.length; off += otaMaxChunk) {
        if (_otaCancel) {
          await send(T.ota, pOtaAbort(), ack: false);
          return 'Dibatalkan';
        }
        final end = off + otaMaxChunk < bin.length ? off + otaMaxChunk : bin.length;
        st = await send(T.ota, pOtaChunk(off, bin.sublist(off, end)));
        if (st != Status.ok) {
          await send(T.ota, pOtaAbort(), ack: false);
          return fail(st);
        }
        onProgress?.call(end / bin.length);
      }
      await _m.invokeMethod('otaRestartExpected');    // restart sesudah END bukan "Lokana tertinggal"
      st = await send(T.ota, pOtaEnd());
      return st == Status.ok ? null : fail(st);
    } finally {
      await sub.cancel();
      await _m.invokeMethod('otaPriority', {'on': false});
    }
  }

  // ---------------- Slot teks (TEXT_SLOT, firmware 0.5.3) ----------------
  bool get hasTextSlots => info?.has(Caps.textSlot) ?? false;

  /// Isi slot teks 1-8 dari Lokana. null = firmware lama / tidak ada balasan.
  Future<List<TextSlot>?> listTextSlots() async {
    if (!hasTextSlots) return null;
    final got = <int, TextSlot>{};
    final done = Completer<void>();
    final sub = frames.where((f) => f.$1 == T.textSlot).listen((f) {
      final s = TextSlot.parse(f.$2);
      if (s == null) return;
      got[s.slot] = s;
      if (got.length >= 8 && !done.isCompleted) done.complete();
    });
    try {
      final st = await send(T.textSlot, pTextSlotList());
      if (st != Status.ok) return null;
      await done.future.timeout(const Duration(seconds: 4), onTimeout: () {});
      return [for (var i = 1; i <= 8; i++) got[i] ?? TextSlot(i, 0, 0, 0, '')];
    } finally {
      await sub.cancel();
    }
  }

  Future<int> showTextSlot(int slot, {int durationS = 0}) => send(T.textSlot, pTextSlotShow(slot, durationS: durationS));
  Future<int> deleteTextSlot(int slot) => send(T.customText, pCustomText('', slot: slot));

  // ---------------- Notifikasi (v0.5) ----------------
  Future<NotifStatus> notifStatus() async =>
      NotifStatus.fromMap(await _m.invokeMapMethod<String, dynamic>('notifStatus') ?? const {});
  Future<void> setNotifEnabled(bool on) => _m.invokeMethod('setNotif', {'enabled': on});
  Future<void> setCallsEnabled(bool on) => _m.invokeMethod('setNotif', {'calls': on});
  Future<void> setNotifApp(String pkg, bool on) => _m.invokeMethod('setNotif', {'app': pkg, 'on': on});
  Future<void> openNotifAccess() => _m.invokeMethod('openNotifAccess');
  Future<void> openBattery() => _m.invokeMethod('openBattery');
  Future<int> testNotif() async => await _m.invokeMethod<int>('testNotif') ?? Status.noAck;

  Future<List<AppEntry>> installedApps() async {
    final list = await _m.invokeListMethod<Map>('installedApps') ?? const [];
    return [
      for (final e in list) AppEntry(e['package'] as String, e['label'] as String, e['icon'] as Uint8List?),
    ];
  }
}

class NotifStatus {
  final bool access, enabled, calls, battery;
  final Set<String> apps;
  NotifStatus(this.access, this.enabled, this.calls, this.battery, this.apps);
  factory NotifStatus.fromMap(Map<String, dynamic> m) => NotifStatus(
        m['access'] == true,
        m['enabled'] != false,
        m['calls'] != false,
        m['battery'] == true,
        {...(m['apps'] as List? ?? const []).cast<String>()},
      );
}

class AppEntry {
  final String package, label;
  final Uint8List? icon;
  AppEntry(this.package, this.label, this.icon);
}
