"""Salin font OLED Lokana (Adafruit GFX) ke aplikasi supaya pratinjau teks sama persis dengan Lokana.

Sumber: font piksel bawaan (glcdfont.c, 5x7) dan 12 font GFX yang dipakai modul Teks
(FreeSans, FreeSansBold, FreeSerif, FreeMonoBold; 9/12/18 pt). Hasil: app/lib/oled_fonts.dart.

Jalankan dari folder firmware/ setelah `pio run -e supermini` (library sudah terunduh):
    python tools/gen_oled_fonts.py
"""
import base64, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
GFX = os.path.join(HERE, "..", ".pio", "libdeps", "supermini", "Adafruit GFX Library")
OUT = os.path.join(HERE, "..", "..", "app", "lib", "oled_fonts.dart")
# Urutan = ID font CUSTOM_TEXT 1..4, ukuran 1..3 (lihat text_module.cpp)
FONTS = ["FreeSans", "FreeSansBold", "FreeSerif", "FreeMonoBold"]
SIZES = [9, 12, 18]


def hexbytes(s):
    return bytes(int(h, 16) for h in re.findall(r"0x([0-9A-Fa-f]{2})", s))


def gfx_font(name):
    src = open(os.path.join(GFX, "Fonts", name + ".h"), encoding="utf-8").read()
    bm = hexbytes(re.search(r"Bitmaps\[\] PROGMEM = \{(.*?)\};", src, re.S).group(1))
    gl = re.search(r"Glyphs\[\] PROGMEM = \{(.*?)\};", src, re.S).group(1)
    gl = re.sub(r"//[^\n]*", "", gl)                 # komentar berisi '{' / '}' (glyph 0x7B/0x7D)
    glyphs = [int(v) for t in re.findall(r"\{([^}]*)\}", gl) for v in t.split(",")]
    first, last, yadv = re.search(r"\(GFXglyph \*\)\w+,\s*(0x[0-9A-Fa-f]+),\s*(0x[0-9A-Fa-f]+),\s*(\d+)\}", src).groups()
    return bm, glyphs, int(first, 16), int(last, 16), int(yadv)


def main():
    if not os.path.isdir(GFX):
        sys.exit("Adafruit GFX belum terunduh: jalankan `pio run -e supermini` dulu")
    glcd = hexbytes(re.search(r"font\[\] PROGMEM = \{(.*?)\};",
                              open(os.path.join(GFX, "glcdfont.c"), encoding="utf-8").read(), re.S).group(1))
    out = [
        "// DIBUAT OTOMATIS oleh firmware/tools/gen_oled_fonts.py — jangan diedit manual.",
        "// Font OLED Lokana dari Adafruit GFX Library (BSD): glcdfont 5x7 dan FreeFonts (GNU FreeFont,",
        "// GPLv3 + font exception). Dipakai pratinjau teks supaya sama persis dengan layar Lokana.",
        "// ignore_for_file: lines_longer_than_80_chars",
        "import 'dart:convert';",
        "import 'dart:typed_data';",
        "",
        "/// Satu font GFX: bitmap glyph (bit MSB dulu, bersambung) + tabel glyph",
        "/// (offset, w, h, xAdvance, xOffset, yOffset) per karakter [first]..[last].",
        "class GfxFont {",
        "  final Uint8List bitmap;",
        "  final List<int> glyphs;",
        "  final int first, last, yAdvance;",
        "  GfxFont(String b64, this.glyphs, this.first, this.last, this.yAdvance) : bitmap = base64.decode(b64);",
        "}",
        "",
        "/// Font piksel bawaan (classic 5x7): 5 byte kolom per karakter, bit 0 = baris atas.",
        "final Uint8List glcdFont = base64.decode('%s');" % base64.b64encode(glcd).decode(),
        "",
        "/// [font 1..4][ukuran 1..3] sama dengan GFX_FONTS di firmware/src/modules/text_module.cpp.",
        "final List<List<GfxFont>> gfxFonts = [",
    ]
    for f in FONTS:
        out.append("  [")
        for sz in SIZES:
            bm, gl, first, last, yadv = gfx_font("%s%dpt7b" % (f, sz))
            out.append("    GfxFont('%s', const %s, %d, %d, %d), // %s %d pt"
                       % (base64.b64encode(bm).decode(), gl, first, last, yadv, f, sz))
        out.append("  ],")
    out.append("];")
    open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
    print("ok:", os.path.normpath(OUT), os.path.getsize(OUT), "byte")


main()
