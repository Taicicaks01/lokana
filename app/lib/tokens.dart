// Token desain Lokana (docs/DESIGN.md §2). Dipakai lewat `context.lk`:
//   Container(color: context.lk.surface2)
// Warna aksen pilihan pengguna tetap menjadi seed ColorScheme; bentuk Lokana Cube & ikon selalu pink brand.
import 'package:material_ui/material_ui.dart';

@immutable
class LokanaTokens extends ThemeExtension<LokanaTokens> {
  final Color bg;        // latar halaman
  final Color surface;   // kartu
  final Color surface2;  // segmen, isian dalam kartu
  final Color line;      // garis & tepi kartu
  final Color text;
  final Color muted;     // keterangan (kontras ≥ 4.5:1)
  final Color pink;      // pink brand: tombol utama, isian aktif
  final Color onPink;    // teks di atas pink brand
  final Color pinkText;  // pink sebagai teks: label aktif, tautan
  final Color pinkSoft;  // latar ikon, tab aktif
  final Color hero;      // kartu hero, tetap gelap di mode terang ("layar OLED")
  final Color ok;        // titik "Tersambung"

  const LokanaTokens({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.text,
    required this.muted,
    required this.pink,
    required this.onPink,
    required this.pinkText,
    required this.pinkSoft,
    required this.hero,
    required this.ok,
  });

  static const brandPink = Color(0xFFF478AA);

  static const dark = LokanaTokens(
    bg: Color(0xFF121016),
    surface: Color(0xFF1C1920),
    surface2: Color(0xFF26222B),
    line: Color(0x14FFFFFF),          // putih 8%
    text: Color(0xFFF6F1F5),
    muted: Color(0xFFA69CA8),
    pink: brandPink,
    onPink: Color(0xFF2B0F1C),
    pinkText: Color(0xFFF78BB6),
    pinkSoft: Color(0x29F478AA),      // pink 16%
    hero: Color(0xFF0E0C11),
    ok: Color(0xFF6EE7A8),
  );

  static const light = LokanaTokens(
    bg: Color(0xFFFBF7F9),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF3ECF0),
    line: Color(0x141B1720),          // #1B1720 8%
    text: Color(0xFF1B1720),
    muted: Color(0xFF655D6A),
    pink: brandPink,
    onPink: Color(0xFF2B0F1C),
    pinkText: Color(0xFFB8336A),
    pinkSoft: Color(0x2EF478AA),      // pink 18%
    hero: Color(0xFF1A161E),
    ok: Color(0xFF6EE7A8),
  );

  /// Radius & ukuran bentuk (§2 Bentuk).
  static const rCard = 24.0, rHero = 32.0, rChip = 14.0, rIcon = 14.0, iconBox = 40.0, pad = 16.0;

  @override
  LokanaTokens copyWith({
    Color? bg, Color? surface, Color? surface2, Color? line, Color? text, Color? muted, Color? pink,
    Color? onPink, Color? pinkText, Color? pinkSoft, Color? hero, Color? ok,
  }) =>
      LokanaTokens(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surface2: surface2 ?? this.surface2,
        line: line ?? this.line,
        text: text ?? this.text,
        muted: muted ?? this.muted,
        pink: pink ?? this.pink,
        onPink: onPink ?? this.onPink,
        pinkText: pinkText ?? this.pinkText,
        pinkSoft: pinkSoft ?? this.pinkSoft,
        hero: hero ?? this.hero,
        ok: ok ?? this.ok,
      );

  @override
  LokanaTokens lerp(ThemeExtension<LokanaTokens>? other, double t) {
    if (other is! LokanaTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return LokanaTokens(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2),
      line: l(line, other.line),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      pink: l(pink, other.pink),
      onPink: l(onPink, other.onPink),
      pinkText: l(pinkText, other.pinkText),
      pinkSoft: l(pinkSoft, other.pinkSoft),
      hero: l(hero, other.hero),
      ok: l(ok, other.ok),
    );
  }
}

extension LokanaTokensContext on BuildContext {
  LokanaTokens get lk => Theme.of(this).extension<LokanaTokens>() ?? LokanaTokens.dark;
}
