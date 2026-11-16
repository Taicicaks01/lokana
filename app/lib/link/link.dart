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
  int mtu = 23;
  ({String address, String name})? saved;
  DeviceInfo? info;
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
        mtu = e['mtu'] as int? ?? mtu;
        if (state == LinkState.ready && address != null) saved = (address: address!, name: name ?? 'Lokana');
        if (state == LinkState.idle) phoneRinging = false;
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
}
