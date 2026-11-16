"""Buat bitmap 1-bit tulisan Sansekerta लोचन (locana, "mata") untuk splash boot Lokana.

Hasil: firmware/src/modules/splash_art.h (dua ukuran: layar 64 px dan 32 px).
Font: Baloo 2 (SIL Open Font License), ada di app/assets/fonts/ dan dipakai juga oleh aplikasi.

    pip install pillow
    python firmware/tools/gen_splash.py            # tulis ulang splash_art.h
    python firmware/tools/gen_splash.py --preview  # juga simpan pratinjau PNG di samping file ini

Kata ini tidak butuh penyusunan ulang huruf (tanpa konjungsi), jadi layout BASIC Pillow sudah benar
walau tanpa libraqm.
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FONT = os.path.join(ROOT, "app", "assets", "fonts", "Baloo2-Variable.ttf")
OUT = os.path.join(ROOT, "firmware", "src", "modules", "splash_art.h")
WORD = "लोचन"

# (nama, tinggi px, ketebalan wght, ambang 0-255)
SIZES = [("SPLASH64", 34, 700, 140), ("SPLASH32", 22, 800, 140)]


def render(h, wght, thr):
    font = ImageFont.truetype(FONT, 400, layout_engine=ImageFont.Layout.BASIC)
    font.set_variation_by_axes([wght])
    im = Image.new("L", (2000, 800))
    ImageDraw.Draw(im).text((40, 40), WORD, font=font, fill=255)
    im = im.crop(im.getbbox())
    w = round(im.width * h / im.height)
    return im.resize((w, h), Image.LANCZOS).point(lambda v: 255 if v >= thr else 0)


def headline(im):
    """Baris garis atas (shirorekha): baris yang terisi >= 75% lebar. Hasil (atas, bawah) inklusif."""
    rows = [y for y in range(im.height) if sum(im.getpixel((x, y)) > 0 for x in range(im.width)) >= 0.75 * im.width]
    if not rows:
        sys.exit("garis atas tidak ditemukan")
    return rows[0], rows[-1]


def to_bytes(im):
    out = []
    for y in range(im.height):
        for k in range(0, im.width, 8):
            v = 0
            for i in range(8):
                if k + i < im.width and im.getpixel((k + i, y)):
                    v |= 0x80 >> i
            out.append(v)
    return out


def main():
    lines = [
        "// Dibuat oleh firmware/tools/gen_splash.py — jangan diedit manual.",
        "// लोचन (locana, \"mata\"), font Baloo 2 (SIL Open Font License). Format drawBitmap: MSB = kiri.",
        "#pragma once",
        "#include <Arduino.h>",
        "",
    ]
    for name, h, wght, thr in SIZES:
        im = render(h, wght, thr)
        y0, y1 = headline(im)
        data = to_bytes(im)
        lines += [
            "// %dx%d, garis atas baris %d-%d" % (im.width, im.height, y0, y1),
            "static const uint8_t %s_W = %d, %s_H = %d, %s_LINE_Y0 = %d, %s_LINE_Y1 = %d;"
            % (name, im.width, name, im.height, name, y0, name, y1),
            "static const uint8_t %s[] PROGMEM = {" % name,
        ]
        for i in range(0, len(data), 16):
            lines.append("  " + ", ".join("0x%02x" % v for v in data[i:i + 16]) + ",")
        lines += ["};", ""]
        if "--preview" in sys.argv:
            im.resize((im.width * 4, im.height * 4), Image.NEAREST).save(
                os.path.join(os.path.dirname(os.path.abspath(__file__)), name.lower() + ".png"))
        print("%s: %dx%d, garis atas %d-%d" % (name, im.width, im.height, y0, y1))
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print("tulis", os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()
