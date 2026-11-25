"""Salin font piksel 5x7 Lokana (Adafruit GFX glcdfont.c, BSD) ke desktop/oled_font.py,
supaya pratinjau OLED di jendela pengaturan sama persis dengan layar Lokana.

Jalankan dari folder repo setelah `pio run -e supermini` (library sudah terunduh):
    python desktop/tools/gen_oled_font.py
"""
import base64
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GFX = os.path.join(HERE, "..", "..", "firmware", ".pio", "libdeps", "supermini", "Adafruit GFX Library")
OUT = os.path.join(HERE, "..", "oled_font.py")


def main():
    path = os.path.join(GFX, "glcdfont.c")
    if not os.path.isfile(path):
        sys.exit("Adafruit GFX belum terunduh: jalankan `pio run -e supermini` di firmware/ dulu")
    src = open(path, encoding="utf-8").read()
    data = bytes(int(h, 16) for h in re.findall(r"0x([0-9A-Fa-f]{2})",
                                                 re.search(r"font\[\] PROGMEM = \{(.*?)\};", src, re.S).group(1)))
    lic = open(os.path.join(GFX, "license.txt"), encoding="utf-8").read().strip()
    b64 = base64.b64encode(data).decode()
    lines = [
        '"""DIBUAT OTOMATIS oleh desktop/tools/gen_oled_font.py - jangan diedit manual.',
        "",
        "Font piksel bawaan Lokana (Adafruit GFX classic 5x7, glcdfont.c): 5 byte kolom per karakter,",
        "bit 0 = baris atas, 8 baris digambar. Lisensi Adafruit GFX Library:",
        "",
    ] + ["    " + l if l else "" for l in lic.splitlines()] + [
        '"""',
        "import base64",
        "",
        "GLCD = base64.b64decode(",
    ]
    for i in range(0, len(b64), 96):
        lines.append('    "%s"' % b64[i:i + 96])
    lines += [")", ""]
    open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print("ditulis: %s (%d byte font)" % (os.path.normpath(OUT), len(data)))


if __name__ == "__main__":
    main()
