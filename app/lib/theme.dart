// Tema aplikasi: mode terang/gelap, warna aksen, dan warna piksel pratinjau OLED.
// Disimpan di HP lewat SharedPreferences (sisi Kotlin), tanpa paket tambahan.
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class AccentColor {
  final String id, label;
  final Color color;
  const AccentColor(this.id, this.label, this.color);
}

class OledColor {
  final String id, label;
  final Color color;
  const OledColor(this.id, this.label, this.color);
}

class AppTheme extends ChangeNotifier {
  AppTheme._();
  static final instance = AppTheme._();
  static const _m = MethodChannel('lokana/link');

  static const accents = [
    AccentColor('lokana', 'Lokana', Color(0xFF2BB3C0)),
    AccentColor('biru', 'Biru', Color(0xFF3D7BF7)),
    AccentColor('ungu', 'Ungu', Color(0xFF7C5CE0)),
    AccentColor('hijau', 'Hijau', Color(0xFF2E9E5B)),
    AccentColor('jingga', 'Jingga', Color(0xFFE8792B)),
    AccentColor('merah', 'Merah muda', Color(0xFFD94F7C)),
    AccentColor('emas', 'Emas', Color(0xFFC9A227)),
  ];

  /// Warna OLED sungguhan: biru muda, putih, kuning, dan hijau tersedia di pasaran.
  static const oledColors = [
    OledColor('biru', 'Biru muda', Color(0xFF9EE7FF)),
    OledColor('putih', 'Putih', Color(0xFFF2F2F2)),
    OledColor('kuning', 'Kuning', Color(0xFFFFD84A)),
    OledColor('hijau', 'Hijau', Color(0xFF7DFFA0)),
  ];

  ThemeMode mode = ThemeMode.system;
  AccentColor accent = accents.first;
  OledColor oled = oledColors.first;
  /// Layar pembuka लोचन saat aplikasi dibuka.
  bool splash = true;

  Future<void> load() async {
    try {
      final p = await _m.invokeMapMethod<String, String>('getPrefs') ?? const {};
      splash = p['app_splash'] != '0';
      mode = ThemeMode.values.firstWhere((m) => m.name == p['theme_mode'], orElse: () => ThemeMode.system);
      accent = accents.firstWhere((a) => a.id == p['theme_accent'], orElse: () => accents.first);
      oled = oledColors.firstWhere((o) => o.id == p['theme_oled'], orElse: () => oledColors.first);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save(String key, String value) async {
    notifyListeners();
    try { await _m.invokeMethod('setPref', {'key': key, 'value': value}); } catch (_) {}
  }

  void setMode(ThemeMode m) { mode = m; _save('theme_mode', m.name); }
  void setAccent(AccentColor a) { accent = a; _save('theme_accent', a.id); }
  void setOled(OledColor o) { oled = o; _save('theme_oled', o.id); }
  void setSplash(bool on) { splash = on; _save('app_splash', on ? '1' : '0'); }

  ThemeData data(Brightness b) {
    final cs = ColorScheme.fromSeed(seedColor: accent.color, brightness: b);
    return ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      appBarTheme: AppBarTheme(centerTitle: false, backgroundColor: cs.surface, scrolledUnderElevation: 2),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      ),
      chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    );
  }
}
