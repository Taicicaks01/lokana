"""Lokana — generator ikon aplikasi (konsep E1: kubus + gantungan).
Semua ukuran diturunkan dari satu geometri di kanvas 1024 (ikon penuh).
Jalankan dari mana saja: python brand/tools/gen_icons.py  (butuh Pillow: pip install pillow)
Output ditulis ke folder brand/ (menimpa file ikon, README & tools tidak disentuh).
"""
from PIL import Image, ImageDraw
import os, json, math, shutil

S = 1024
BG   = '#1A161E'   # latar gelap
PINK = '#F478AA'   # badan (PETG pink)
SCR  = '#121218'   # layar OLED
EYE  = '#FFFFFF'   # mata

# ---- geometri (unit kanvas 1024) ----
CX = 512
LUG  = dict(x0=CX-70, y0=150, x1=CX+70, y1=290, r=50)
HOLE = dict(cx=CX, cy=212, r=26)
BODY = dict(x0=190, y0=250, x1=834, y1=814, r=140)
SCRN = dict(x0=262, y0=330, x1=762, y1=610, r=56)
EW, EH, EGAP, EY0, ER = 118, 170, 80, 385, 46
EYES = [dict(x0=CX-EGAP/2-EW, y0=EY0, x1=CX-EGAP/2, y1=EY0+EH, r=ER),
        dict(x0=CX+EGAP/2,    y0=EY0, x1=CX+EGAP/2+EW, y1=EY0+EH, r=ER)]

def hexrgb(h, a=255):
    h = h.lstrip('#'); return tuple(int(h[i:i+2], 16) for i in (0, 2, 4)) + (a,)

# ---------------------------------------------------------------- raster
def render(size, bg=BG, mask='square', mono=None, scale=1.0, K=4):
    """mask: 'square' (penuh), 'squircle' (rounded 23.5%), 'circle', 'none' (transparan di luar konten)
    mono: warna tunggal -> siluet (badan & mata terisi, layar & lubang bolong)
    scale: perbesar/perkecil konten terhadap pusat (untuk area aman maskable)."""
    N = size * K; f = N / S * scale; off = N / 2 - S / 2 * f
    T = lambda v: v * f + off
    im = Image.new('RGBA', (N, N), (0, 0, 0, 0) if bg is None else hexrgb(bg))
    d = ImageDraw.Draw(im)
    def rr(g, c): d.rounded_rectangle([T(g['x0']), T(g['y0']), T(g['x1']), T(g['y1'])], radius=g['r']*f, fill=c)
    hole_c = (0, 0, 0, 0) if (bg is None) else hexrgb(bg)
    if mono:
        m = hexrgb(mono)
        rr(LUG, m); rr(BODY, m)
        cut = Image.new('L', (N, N), 0); dc = ImageDraw.Draw(cut)
        dc.rounded_rectangle([T(SCRN['x0']), T(SCRN['y0']), T(SCRN['x1']), T(SCRN['y1'])], radius=SCRN['r']*f, fill=255)
        dc.ellipse([T(HOLE['cx']-HOLE['r']), T(HOLE['cy']-HOLE['r']), T(HOLE['cx']+HOLE['r']), T(HOLE['cy']+HOLE['r'])], fill=255)
        im.paste(hole_c, (0, 0), cut)
        for e in EYES: rr(e, m)
    else:
        rr(LUG, hexrgb(PINK)); rr(BODY, hexrgb(PINK))
        cut = Image.new('L', (N, N), 0); ImageDraw.Draw(cut).ellipse(
            [T(HOLE['cx']-HOLE['r']), T(HOLE['cy']-HOLE['r']), T(HOLE['cx']+HOLE['r']), T(HOLE['cy']+HOLE['r'])], fill=255)
        im.paste(hole_c, (0, 0), cut)
        rr(SCRN, hexrgb(SCR))
        for e in EYES: rr(e, hexrgb(EYE))
    if mask in ('squircle', 'circle'):
        mk = Image.new('L', (N, N), 0); dm = ImageDraw.Draw(mk)
        if mask == 'circle': dm.ellipse([0, 0, N-1, N-1], fill=255)
        else: dm.rounded_rectangle([0, 0, N-1, N-1], radius=int(N*0.235), fill=255)
        out = Image.new('RGBA', (N, N), (0, 0, 0, 0)); out.paste(im, (0, 0), mk); im = out
    return im.resize((size, size), Image.LANCZOS)

# ---------------------------------------------------------------- vektor
def rr_path(g, T, f, Ty=None):
    Ty = Ty or T
    x0, y0, x1, y1 = T(g['x0']), Ty(g['y0']), T(g['x1']), Ty(g['y1']); r = g['r']*f
    n = lambda v: ('%.3f' % v).rstrip('0').rstrip('.')
    return ('M%s,%s H%s A%s,%s 0 0 1 %s,%s V%s A%s,%s 0 0 1 %s,%s H%s A%s,%s 0 0 1 %s,%s V%s A%s,%s 0 0 1 %s,%s Z' % tuple(map(n, (
        x0+r, y0, x1-r, r, r, x1, y0+r, y1-r, r, r, x1-r, y1, x0+r, r, r, x0, y1-r, y0+r, r, r, x0+r, y0))))
def circ_path(c, T, f, Ty=None):
    Ty = Ty or T
    cx, cy, r = T(c['cx']), Ty(c['cy']), c['r']*f
    n = lambda v: ('%.3f' % v).rstrip('0').rstrip('.')
    return 'M%s,%s A%s,%s 0 1 0 %s,%s A%s,%s 0 1 0 %s,%s Z' % tuple(map(n, (cx-r, cy, r, r, cx+r, cy, r, r, cx-r, cy)))

def layers(view, size_in, pad, cy=512):
    """kembalikan dict path per peran di viewport `view`, konten 1024 dipetakan ke [pad, view-pad]."""
    f = (view - 2*pad) / size_in; o = view/2 - S/2*f
    T = lambda v: v*f + o
    Ty = lambda v: (v - cy + S/2)*f + o
    return dict(
        lug=rr_path(LUG, T, f, Ty) + ' ' + circ_path(HOLE, T, f, Ty),
        body=rr_path(BODY, T, f, Ty), screen=rr_path(SCRN, T, f, Ty),
        eyes=' '.join(rr_path(e, T, f, Ty) for e in EYES),
        silhouette=rr_path(BODY, T, f, Ty) + ' ' + rr_path(SCRN, T, f, Ty),
    )

def vd(view_dp, view, paths):
    out = ['<?xml version="1.0" encoding="utf-8"?>',
           '<vector xmlns:android="http://schemas.android.com/apk/res/android"',
           '    android:width="%ddp" android:height="%ddp"' % (view_dp, view_dp),
           '    android:viewportWidth="%s" android:viewportHeight="%s">' % (view, view)]
    for color, d, eo in paths:
        out.append('    <path android:fillColor="%s"%s\n        android:pathData="%s" />' % (
            color, ' android:fillType="evenOdd"' if eo else '', d))
    out.append('</vector>')
    return '\n'.join(out) + '\n'

def svg(view, paths, bg=None, rx=0):
    o = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s">' % (view, view)]
    if bg: o.append('<rect width="%s" height="%s" rx="%s" fill="%s"/>' % (view, view, rx, bg))
    for color, d, eo in paths:
        o.append('<path fill="%s"%s d="%s"/>' % (color, ' fill-rule="evenodd"' if eo else '', d))
    o.append('</svg>')
    return '\n'.join(o) + '\n'

# ================================================================= tulis
R = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
def W(p, data):
    p = os.path.join(R, p); os.makedirs(os.path.dirname(p), exist_ok=True)
    if isinstance(data, Image.Image): data.save(p, optimize=True)
    else: open(p, 'w', newline='\n').write(data)

# --- master
full = layers(1024, 1024, 0)
color_paths = [(PINK, full['lug'], True), (PINK, full['body'], False), (SCR, full['screen'], False), (EYE, full['eyes'], False)]
W('master/lokana_icon.svg', svg(1024, color_paths, BG, 240))
W('master/lokana_icon_full.svg', svg(1024, color_paths, BG, 0))
W('master/lokana_mark.svg', svg(1024, color_paths))
W('master/lokana_icon_1024.png', render(1024, mask='squircle'))
W('master/lokana_mark_512.png', render(512, bg=None, mask='none'))

# --- Android adaptive (API 26+): kanvas 108dp, konten di area 72dp tengah (pad 18)
a = layers(108, 1024, 18)
res = 'android/res/'
W(res + 'drawable/ic_launcher_foreground.xml', vd(108, 108, [
    (PINK, a['lug'], True), (PINK, a['body'], False), (SCR, a['screen'], False), (EYE, a['eyes'], False)]))
W(res + 'drawable/ic_launcher_monochrome.xml', vd(108, 108, [
    ('#FFFFFFFF', a['lug'], True), ('#FFFFFFFF', a['silhouette'], True), ('#FFFFFFFF', a['eyes'], False)]))
W(res + 'values/ic_launcher_background.xml',
  '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">%s</color>\n</resources>\n' % BG)
adaptive = ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background" />\n'
            '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
            '    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />\n'
            '</adaptive-icon>\n')
W(res + 'mipmap-anydpi-v26/ic_launcher.xml', adaptive)
W(res + 'mipmap-anydpi-v26/ic_launcher_round.xml', adaptive)
# --- legacy PNG (Android < 8)
for q, px in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
    W(res + 'mipmap-%s/ic_launcher.png' % q, render(px, mask='squircle'))
    W(res + 'mipmap-%s/ic_launcher_round.png' % q, render(px, mask='circle'))
# --- ikon notifikasi (siluet putih, 24dp)
n = layers(24, 672, 1.0, cy=482)   # badan+gantungan (644x664 unit) memenuhi 22dp
W(res + 'drawable/ic_stat_lokana.xml', vd(24, 24, [
    ('#FFFFFFFF', n['lug'], True), ('#FFFFFFFF', n['silhouette'], True), ('#FFFFFFFF', n['eyes'], False)]))

# --- Play Store
W('store/play_store_512.png', render(512, mask='square').convert('RGB'))

# --- iOS (Xcode 14+, satu ukuran 1024; mode gelap = latar transparan)
ios = 'ios/AppIcon.appiconset/'
W(ios + 'AppIcon-1024.png', render(1024, mask='square').convert('RGB'))
W(ios + 'AppIcon-1024-dark.png', render(1024, bg=None, mask='none'))
W(ios + 'Contents.json', json.dumps({
    'images': [
        {'filename': 'AppIcon-1024.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'},
        {'appearances': [{'appearance': 'luminosity', 'value': 'dark'}],
         'filename': 'AppIcon-1024-dark.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}],
    'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')

# --- Web / PWA (untuk Lokana Web nanti)
W('web/favicon.svg', svg(1024, color_paths, BG, 240))
W('web/favicon-32.png', render(32, mask='squircle'))
W('web/apple-touch-icon.png', render(180, mask='square').convert('RGB'))
W('web/icon-192.png', render(192, mask='squircle'))
W('web/icon-512.png', render(512, mask='squircle'))
W('web/icon-maskable-512.png', render(512, mask='square', scale=0.86))
print('ok')
