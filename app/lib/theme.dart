// Tema aplikasi: mode terang/gelap, warna aksen, dan warna piksel pratinjau OLED.
// Disimpan di HP lewat SharedPreferences (sisi Kotlin), tanpa paket tambahan.
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'tokens.dart';

export 'tokens.dart';

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
    // Pink PETG casing & ikon (brand/README.md). Toska = warna bawaan lama.
    AccentColor('lokana', 'Lokana', Color(0xFFF478AA)),
    AccentColor('toska', 'Toska', Color(0xFF2BB3C0)),
    AccentColor('biru', 'Biru', Color(0xFF3D7BF7)),
    AccentColor('ungu', 'Ungu', Color(0xFF7C5CE0)),
    AccentColor('hijau', 'Hijau', Color(0xFF2E9E5B)),
    AccentColor('jingga', 'Jingga', Color(0xFFE8792B)),
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
      _p = {...p};
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

  // Setelan terakhir halaman (font teks, ketajaman gambar, dll.) supaya tidak perlu diatur ulang.
  Map<String, String> _p = {};
  String? pref(String key) => _p[key];
  int prefInt(String key, int def) => int.tryParse(_p[key] ?? '') ?? def;
  bool prefBool(String key, bool def) => _p[key] == null ? def : _p[key] == '1';
  void remember(String key, Object value) {
    final v = value is bool ? (value ? '1' : '0') : '$value';
    if (_p[key] == v) return;
    _p[key] = v;
    _m.invokeMethod('setPref', {'key': key, 'value': v}).catchError((_) => null);
  }

  void setMode(ThemeMode m) { mode = m; _save('theme_mode', m.name); }
  void setAccent(AccentColor a) { accent = a; _save('theme_accent', a.id); }
  void setOled(OledColor o) { oled = o; _save('theme_oled', o.id); }
  void setSplash(bool on) { splash = on; _save('app_splash', on ? '1' : '0'); }

  /// Judul memakai Baloo 2 (huruf yang sama dengan logo लोचन), isi tetap font sistem.
  static TextStyle? _brand(TextStyle? s, double weight) => s?.copyWith(
      fontFamily: 'Baloo2', fontVariations: [FontVariation('wght', weight)], height: 1.2, letterSpacing: 0);

  /// Tema dari token docs/DESIGN.md §2. Permukaan, teks, dan garis selalu dari token Lokana; warna aksen
  /// pilihan pengguna menjadi seed ColorScheme. Aksen "Lokana" memakai pink brand persis:
  /// `primary` = pink sebagai teks (kontras ≥ 4.5:1), tombol utama = pink brand #F478AA dengan teks gelap.
  ThemeData data(Brightness b) {
    final dark = b == Brightness.dark;
    final lk = dark ? LokanaTokens.dark : LokanaTokens.light;
    final brand = accent.id == 'lokana';
    var cs = ColorScheme.fromSeed(seedColor: accent.color, brightness: b).copyWith(
      surface: lk.bg,
      onSurface: lk.text,
      onSurfaceVariant: lk.muted,
      surfaceContainerLowest: lk.bg,
      surfaceContainerLow: lk.surface,
      surfaceContainer: lk.surface,
      surfaceContainerHigh: lk.surface2,
      surfaceContainerHighest: lk.surface2,
      outlineVariant: lk.line,
      // Aksi kedua = permukaan netral (§1.4: hanya aksi utama yang berwarna penuh)
      secondaryContainer: lk.surface2,
      onSecondaryContainer: lk.text,
    );
    if (brand) {
      cs = cs.copyWith(
        primary: lk.pinkText,
        onPrimary: dark ? lk.onPink : Colors.white,
        primaryContainer: lk.pinkSoft,
        onPrimaryContainer: lk.pinkText,
      );
    }
    final soft = brand ? lk.pinkSoft : cs.primaryContainer;        // latar ikon, tab & pilihan aktif
    final activeText = brand ? lk.pinkText : cs.onPrimaryContainer;

    final base = ThemeData(colorScheme: cs, useMaterial3: true, brightness: b);
    final tt = base.textTheme;
    // Ukuran §2: judul layar 28, nama perangkat 24, judul seksi 18, isi 15, keterangan 13, label kecil 12
    final text = tt.copyWith(
      displaySmall: _brand(tt.displaySmall, 700),
      headlineLarge: _brand(tt.headlineLarge, 700),
      headlineMedium: _brand(tt.headlineMedium?.copyWith(fontSize: 28), 700),
      headlineSmall: _brand(tt.headlineSmall?.copyWith(fontSize: 24), 700),
      titleLarge: _brand(tt.titleLarge?.copyWith(fontSize: 24), 650),
      titleMedium: _brand(tt.titleMedium?.copyWith(fontSize: 18), 650),
      bodyLarge: tt.bodyLarge?.copyWith(fontSize: 15),
      bodyMedium: tt.bodyMedium?.copyWith(fontSize: 15),
      bodySmall: tt.bodySmall?.copyWith(fontSize: 13, color: lk.muted),
      labelSmall: tt.labelSmall?.copyWith(fontSize: 12),
    ).apply(bodyColor: lk.text, displayColor: lk.text);
    final chipRadius = BorderRadius.circular(LokanaTokens.rChip);
    const pill = StadiumBorder();
    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: lk.bg,
      canvasColor: lk.bg,
      extensions: [lk],
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: lk.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LokanaTokens.rCard), side: BorderSide(color: lk.line)),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        toolbarHeight: 64,
        backgroundColor: lk.bg,
        foregroundColor: lk.text,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: text.headlineMedium,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: lk.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: soft,
        iconTheme: WidgetStateProperty.resolveWith((s) =>
            IconThemeData(color: s.contains(WidgetState.selected) ? activeText : lk.muted)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => text.labelSmall?.copyWith(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? activeText : lk.muted)),
      ),
      snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: chipRadius)),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: pill,
          minimumSize: const Size(64, 52),
          textStyle: text.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
          backgroundColor: brand ? lk.pink : null,
          foregroundColor: brand ? lk.onPink : null,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            shape: pill, minimumSize: const Size(64, 48), side: BorderSide(color: lk.line, width: 1.5)),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(48, 48))),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          foregroundColor: lk.text,                  // tanpa ini segmen biasa ikut berwarna aktif
          selectedBackgroundColor: soft,
          selectedForegroundColor: activeText,
          side: BorderSide(color: lk.line, width: 1.5),
          minimumSize: const Size(48, 48),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: chipRadius),
        side: BorderSide(color: lk.line),
        backgroundColor: lk.surface,
        selectedColor: soft,
        checkmarkColor: activeText,
        labelStyle: text.labelLarge?.copyWith(color: lk.text, fontSize: 14),
        secondaryLabelStyle: text.labelLarge?.copyWith(color: activeText, fontSize: 14, fontWeight: FontWeight.w600),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lk.surface2,
        border: OutlineInputBorder(borderRadius: chipRadius, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: chipRadius, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: chipRadius, borderSide: BorderSide(color: cs.primary, width: 2)),
      ),
      listTileTheme: ListTileThemeData(
          shape: RoundedRectangleBorder(borderRadius: chipRadius), iconColor: lk.muted, textColor: lk.text),
      dividerTheme: DividerThemeData(color: lk.line, space: 1),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: lk.surface, surfaceTintColor: Colors.transparent),
      dialogTheme: DialogThemeData(backgroundColor: lk.surface, surfaceTintColor: Colors.transparent),
      popupMenuTheme: PopupMenuThemeData(color: lk.surface2, surfaceTintColor: Colors.transparent),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }
}
