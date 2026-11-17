# Lokana Cube v1 — case 3D print (Fusion 360 API script)
# Jalankan di Fusion: Utilities > Scripts and Add-Ins, atau lewat MCP Fusion.
# Semua ukuran dalam mm. Ubah angka di P lalu jalankan ulang di desain kosong.
#
# Sumbu (Fusion Z-up):  X = lebar (kiri-kanan), Y = kedalaman (0 = muka depan, + ke belakang),
#                       Z = tinggi (0 = alas).  Muka depan (layar) menghadap -Y.
#
# Susunan dari depan ke belakang: OLED -> ESP32-C3 Super Mini -> TP4056 Type-C -> LiPo 102530 -> tutup.
# Dua port: USB-C Super Mini (program/data) di SISI KANAN, USB-C TP4056 (charge) di BAWAH.
# Super Mini berbaring di bawah (USB ke kanan); TP4056 tegak merapat dinding kiri (USB ke bawah);
# saklar di sisi kiri, buzzer di kanan atas, sensor sentuh di atas.

import adsk.core, adsk.fusion

P = dict(
    wall=1.6,      # dinding samping/atas/bawah
    front=1.2,     # dinding depan (di sekitar layar)
    lid=1.6,       # tebal tutup belakang
    clr=0.4,       # kelonggaran tiap sisi rongga
    gap=0.3,       # celah antar lapisan komponen
    corner_r=4.0,  # radius sudut tampak depan
    edge_r=1.5,    # fillet tepi depan & belakang

    oled_w=27.3, oled_h=27.8, oled_t=4.3,   # modul OLED 0.96" (tanpa header pin)
    oled_glass_from_top=4.6,                # tepi atas PCB -> tepi atas kaca
    win_from_top=11.6,                      # tepi atas PCB -> pusat area menyala
    win_w=25.0, win_h=13.6, win_r=1.2, win_chamfer=0.6,

    sm_w=18.0, sm_h=22.5, sm_t=4.5,         # ESP32-C3 Super Mini
    tp_w=17.3, tp_h=28.0, tp_t=4.9,         # TP4056 Type-C + proteksi
    pcb_t=1.0, usbc_t=3.2,                  # tebal PCB & tinggi soket USB-C
    board_inset=0.3,                        # jarak board dari dinding kiri & lantai
    cavity_r=0.6,                           # radius sudut rongga dalam
    usb_open_w=9.6, usb_open_h=4.0, usb_open_r=1.6,
    usb_pocket=0.9,                         # cekungan luar agar steker masuk penuh

    bat_w=26.0, bat_l=31.0, bat_t=10.0,     # LiPo 102530 (+ toleransi, termasuk ujung proteksi)

    sw_len=8.5, sw_thk=3.5, sw_h=4.4,       # saklar SS12D00
    sw_slot_len=4.8, sw_slot_w=2.4,
    bz_d=9.0, bz_h=5.5,                     # buzzer pasif
    touch_w=11.5, touch_d=8.0, touch_pocket=0.6, dimple_d=6.0, dimple=0.3,

    lug_w=7.0, lug_d=6.0, lug_h=5.0, lug_hole=3.0,   # kuping gantungan kunci
    tab_len=12.0, tab_t=0.9, tab_depth=3.0,          # lidah jepit tutup
    rib=1.45, rib_gap=0.2,                           # rusuk penahan (tonjolan dari dinding, celah ke komponen)
)

FO = adsk.fusion.FeatureOperations
NEW, JOIN, CUT = FO.NewBodyFeatureOperation, FO.JoinFeatureOperation, FO.CutFeatureOperation
VI = adsk.core.ValueInput.createByReal


def mm(v):
    return v / 10.0


def W(w, h, d):  # koordinat logis (lebar, tinggi, kedalaman) -> titik dunia (cm)
    return adsk.core.Point3D.create(mm(w), mm(d), mm(h))


def plane(comp, axis, c):
    base = {'w': comp.yZConstructionPlane, 'd': comp.xZConstructionPlane, 'h': comp.xYConstructionPlane}[axis]
    if abs(c) < 1e-9:
        return base
    pi = comp.constructionPlanes.createInput()
    pi.setByOffset(base, VI(mm(c)))
    pl = comp.constructionPlanes.add(pi)
    pl.isLightBulbOn = False
    return pl


def rrect(sk, a, b, r):
    lines = sk.sketchCurves.sketchLines.addTwoPointRectangle(sk.modelToSketchSpace(a), sk.modelToSketchSpace(b))
    if r <= 0:
        return
    L = [lines.item(i) for i in range(lines.count)]
    corners = []
    for i in range(4):
        for j in range(i + 1, 4):
            for pi in (L[i].startSketchPoint, L[i].endSketchPoint):
                for pj in (L[j].startSketchPoint, L[j].endSketchPoint):
                    if pi.geometry.distanceTo(pj.geometry) < 1e-7:
                        corners.append((L[i], pi.geometry.copy(), L[j], pj.geometry.copy()))
    for (la, pa, lb, pb) in corners:
        sk.sketchCurves.sketchArcs.addFillet(la, pa, lb, pb, mm(r))


def extrude(comp, prof, length, op, parts=None):
    ex = comp.features.extrudeFeatures
    ei = ex.createInput(prof, op)
    ei.setSymmetricExtent(VI(mm(length)), True)
    if parts is not None:
        ei.participantBodies = parts
    return ex.add(ei)


def box(comp, w0, w1, h0, h1, d0, d1, axis, op, r=0.0, parts=None):
    wc, hc, dc = (w0 + w1) / 2, (h0 + h1) / 2, (d0 + d1) / 2
    if axis == 'h':
        a, b, length, c = W(w0, hc, d0), W(w1, hc, d1), h1 - h0, hc
    elif axis == 'd':
        a, b, length, c = W(w0, h0, dc), W(w1, h1, dc), d1 - d0, dc
    else:
        a, b, length, c = W(wc, h0, d0), W(wc, h1, d1), w1 - w0, wc
    sk = comp.sketches.add(plane(comp, axis, c))
    rrect(sk, a, b, r)
    f = extrude(comp, sk.profiles.item(0), length, op, parts)
    sk.isVisible = False
    return f


def cyl(comp, axis, w, h, d, dia, length, op, parts=None):
    c = {'w': w, 'h': h, 'd': d}[axis]
    sk = comp.sketches.add(plane(comp, axis, c))
    sk.sketchCurves.sketchCircles.addByCenterRadius(sk.modelToSketchSpace(W(w, h, d)), mm(dia / 2))
    f = extrude(comp, sk.profiles.item(0), length, op, parts)
    sk.isVisible = False
    return f


def face_by_normal(body, n, coord_index, coord_mm):
    for f in body.faces:
        if f.geometry.surfaceType != adsk.core.SurfaceTypes.PlaneSurfaceType:
            continue
        ok, nv = f.evaluator.getNormalAtPoint(f.pointOnFace)
        c = (f.pointOnFace.x, f.pointOnFace.y, f.pointOnFace.z)[coord_index]
        if ok and abs(nv.x - n[0]) < 1e-6 and abs(nv.y - n[1]) < 1e-6 and abs(nv.z - n[2]) < 1e-6 \
                and abs(c - mm(coord_mm)) < 1e-5:
            return f
    raise RuntimeError('muka tidak ditemukan %s @ %s' % (n, coord_mm))


def fillet(comp, edges, r):
    col = adsk.core.ObjectCollection.create()
    for e in edges:
        col.add(e)
    fi = comp.features.filletFeatures.createInput()
    fi.edgeSetInputs.addConstantRadiusEdgeSet(col, VI(mm(r)), True)
    return comp.features.filletFeatures.add(fi)


def chamfer(comp, edges, dist):
    col = adsk.core.ObjectCollection.create()
    for e in edges:
        col.add(e)
    ci = comp.features.chamferFeatures.createInput2()
    ci.chamferEdgeSets.addEqualDistanceChamferEdgeSet(col, VI(mm(dist)), True)
    return comp.features.chamferFeatures.add(ci)


def geometry(p):
    g = {}
    g['in_w'] = p['oled_w'] + 2 * p['clr']
    g['in_h'] = max(p['oled_h'], p['bat_l'], p['tp_h']) + 2 * p['clr']
    g['out_w'] = g['in_w'] + 2 * p['wall']
    g['out_h'] = g['in_h'] + 2 * p['wall']
    g['inL'], g['inR'] = -g['in_w'] / 2, g['in_w'] / 2
    g['floor'], g['ceil'] = p['wall'], g['out_h'] - p['wall']
    # lapisan kedalaman
    g['d_oled0'] = p['front']
    g['d_oled1'] = g['d_oled0'] + p['oled_t']
    g['d_sm0'] = g['d_oled1'] + p['gap']
    g['d_sm1'] = g['d_sm0'] + p['sm_t']
    g['d_tp0'] = g['d_sm1'] + p['gap']
    g['d_tp1'] = g['d_tp0'] + p['tp_t']
    g['d_bat0'] = g['d_tp1'] + p['gap']
    g['d_bat1'] = g['d_bat0'] + p['bat_t']
    g['body_d'] = g['d_bat1'] + p['gap']
    g['out_d'] = g['body_d'] + p['lid']
    # OLED duduk di lantai rongga; jendela mengikuti area menyala
    g['oled_h0'] = g['floor'] + 0.2
    g['oled_h1'] = g['oled_h0'] + p['oled_h']
    g['win_hc'] = g['oled_h1'] - p['win_from_top']
    # port USB-C (soket di sisi komponen, PCB menghadap depan)
    g['bL'] = g['inL'] + p['board_inset']
    g['bF'] = g['floor'] + p['board_inset']
    # Super Mini berbaring: panjang (sm_h) mendatar, merapat dinding kanan, USB-C di tepi kanan
    g['bR'] = g['inR'] - p['board_inset']
    g['smL'] = g['bR'] - p['sm_h']
    g['sm_usb_h'] = g['bF'] + p['sm_w'] / 2
    g['sm_usb_d'] = g['d_sm0'] + p['pcb_t'] + p['usbc_t'] / 2
    g['tp_usb_w'] = g['bL'] + p['tp_w'] / 2
    g['tp_usb_d'] = g['d_tp0'] + p['pcb_t'] + p['usbc_t'] / 2
    # saklar (kiri bawah, lapisan Super Mini, di sebelah kiri Super Mini)
    g['sw_h0'] = g['floor'] + 1.5
    g['sw_hc'] = g['sw_h0'] + p['sw_len'] / 2
    g['sw_dc'] = (g['d_sm0'] + g['d_sm1']) / 2
    # buzzer (kanan atas, berbaring, menghadap dinding kanan)
    g['bz_w'] = g['inR'] - 0.3 - p['bz_h'] / 2
    g['bz_h'] = 26.0
    g['bz_d'] = (g['d_sm0'] + g['d_tp1']) / 2
    # sensor sentuh (atas)
    g['touch_dc'] = 10.0
    # kuping gantungan kunci (atas, di atas baterai)
    g['lug_dc'] = (g['d_bat0'] + g['d_bat1']) / 2 + 0.6
    return g


def build_case(root, p, g):
    comp = root
    # 1. Blok luar badan
    f = box(comp, -g['out_w'] / 2, g['out_w'] / 2, 0, g['out_h'], 0, g['body_d'], 'd', NEW, r=p['corner_r'])
    body = f.bodies.item(0)
    body.name = 'Lokana_Badan'
    fillet(comp, face_by_normal(body, (0, -1, 0), 1, 0).edges, p['edge_r'])

    # 2. Kuping gantungan kunci
    lw, ld, lh = p['lug_w'], p['lug_d'], p['lug_h']
    top = g['out_h']
    box(comp, -lw / 2, lw / 2, top - 0.5, top + lh, g['lug_dc'] - ld / 2, g['lug_dc'] + ld / 2, 'h', JOIN, parts=[body])
    lug_edges = []
    for e in body.edges:
        a, b = e.startVertex.geometry, e.endVertex.geometry
        if abs(a.z - mm(top + lh)) < 1e-5 and abs(b.z - mm(top + lh)) < 1e-5 and abs(a.x - b.x) > mm(1):
            lug_edges.append(e)
    fillet(comp, lug_edges, ld / 2 - 0.2)
    cyl(comp, 'w', 0, top + lh / 2 - 0.1, g['lug_dc'], p['lug_hole'], lw + 2, CUT, parts=[body])

    # 3. Rongga dalam (terbuka ke belakang)
    box(comp, g['inL'], g['inR'], g['floor'], g['ceil'], p['front'], g['body_d'] + 1, 'd', CUT, r=p['cavity_r'], parts=[body])

    # 4. Jendela layar + chamfer luar
    box(comp, -p['win_w'] / 2, p['win_w'] / 2, g['win_hc'] - p['win_h'] / 2, g['win_hc'] + p['win_h'] / 2,
        -1, p['front'] + 0.5, 'd', CUT, r=p['win_r'], parts=[body])
    ff = face_by_normal(body, (0, -1, 0), 1, 0)
    inner = [e for lp in ff.loops if not lp.isOuter for e in lp.edges]
    chamfer(comp, inner, p['win_chamfer'])

    # 5a. Port program: USB-C Super Mini di dinding kanan (cekungan luar + lubang)
    uh, ud, x1 = g['sm_usb_h'], g['sm_usb_d'], g['out_w'] / 2
    box(comp, x1 - p['usb_pocket'], x1 + 0.5, uh - 6.3, uh + 6.3, ud - 3.6, ud + 3.6, 'w', CUT, r=2.0, parts=[body])
    box(comp, g['inR'] - 0.5, x1 + 0.5, uh - p['usb_open_w'] / 2, uh + p['usb_open_w'] / 2,
        ud - p['usb_open_h'] / 2, ud + p['usb_open_h'] / 2, 'w', CUT, r=p['usb_open_r'], parts=[body])
    # 5b. Port charge: USB-C TP4056 di bawah (cekungan luar + lubang)
    tw, td = g['tp_usb_w'], g['tp_usb_d']
    box(comp, tw - 6.3, tw + 6.3, -0.5, p['usb_pocket'], td - 3.6, td + 3.6, 'h', CUT, r=2.0, parts=[body])
    box(comp, tw - p['usb_open_w'] / 2, tw + p['usb_open_w'] / 2, -0.5, p['wall'] + 0.5,
        td - p['usb_open_h'] / 2, td + p['usb_open_h'] / 2, 'h', CUT, r=p['usb_open_r'], parts=[body])

    # 6. Celah tuas saklar (dinding kiri)
    box(comp, -g['out_w'] / 2 - 1, g['inL'] + 0.5, g['sw_hc'] - p['sw_slot_len'] / 2, g['sw_hc'] + p['sw_slot_len'] / 2,
        g['sw_dc'] - p['sw_slot_w'] / 2, g['sw_dc'] + p['sw_slot_w'] / 2, 'w', CUT, r=0.8, parts=[body])

    # 7. Lubang suara buzzer (dinding kanan)
    for dh, dd in ((0, 0), (2.6, 0), (-2.6, 0), (0, 2.6), (0, -2.6)):
        cyl(comp, 'w', g['out_w'] / 2, g['bz_h'] + dh, g['bz_d'] + dd, 1.2, p['wall'] * 2 + 1, CUT, parts=[body])

    # 8. Kantong sensor sentuh (dalam) + cekungan penanda (luar)
    tw, td = p['touch_w'] + 0.8, p['touch_d'] + 0.8
    box(comp, -tw / 2, tw / 2, g['ceil'] - 0.5, g['ceil'] + p['touch_pocket'], g['touch_dc'] - td / 2,
        g['touch_dc'] + td / 2, 'h', CUT, r=0.5, parts=[body])
    cyl(comp, 'h', 0, g['out_h'], g['touch_dc'], p['dimple_d'], p['dimple'] * 2, CUT, parts=[body])

    # 9b. Rusuk penahan (v1.1): menonjol 1.45 mm dari dinding, cukup kecil untuk dicetak tanpa support
    rb, rg = p['rib'], p['rib_gap']
    L0, R0 = g['inL'], g['inR']
    sm_top = g['bF'] + p['sm_w']
    tp_top = g['bF'] + p['tp_h']
    sw_top = g['sw_h0'] + p['sw_len']
    bz_top = g['bz_h'] + p['bz_d'] / 2
    ribs = [
        # (w0, w1, h0, h1, d0, d1)
        (R0 - rb, R0 + 0.3, sm_top + rg, sm_top + rg + 1.1, g['d_sm0'], g['d_sm1']),            # atas Super Mini
        (L0 - 0.3, L0 + rb, tp_top + rg, tp_top + rg + 1.1, g['d_tp0'], g['d_tp1']),            # atas TP4056
        (L0 - 0.3, L0 + rb, sw_top + rg, sw_top + rg + 1.0, g['d_sm0'], g['d_sm1']),            # atas saklar
        (L0 - 0.3, L0 + rb, g['floor'] - 0.3, g['sw_h0'] - rg, g['d_sm0'], g['d_sm1']),         # bawah saklar
        (R0 - rb, R0 + 0.3, bz_top + 0.3, bz_top + 1.1, g['bz_d'] - p['bz_d'] / 2, g['bz_d'] + p['bz_d'] / 2),  # atas buzzer
    ]
    for (w0, w1, h0, h1, d0, d1) in ribs:
        box(comp, w0, w1, h0, h1, d0, d1, 'd', JOIN, parts=[body])

    # 9. Tutup belakang
    f = box(comp, -g['out_w'] / 2, g['out_w'] / 2, 0, g['out_h'], g['body_d'], g['out_d'], 'd', NEW, r=p['corner_r'])
    lid = f.bodies.item(0)
    lid.name = 'Lokana_Tutup'
    fillet(comp, face_by_normal(lid, (0, 1, 0), 1, g['out_d']).edges, p['edge_r'])
    hc = g['out_h'] / 2
    for s in (-1, 1):
        x_out = s * (g['in_w'] / 2 - 0.05)
        x_in = s * (g['in_w'] / 2 - 0.05 - p['tab_t'])
        box(comp, min(x_out, x_in), max(x_out, x_in), hc - p['tab_len'] / 2, hc + p['tab_len'] / 2,
            g['body_d'] - p['tab_depth'], g['body_d'] + 0.2, 'd', JOIN, parts=[lid])
    # takik kuku untuk membuka tutup
    box(comp, -3, 3, -1, 0.8, g['body_d'] - 0.2, g['out_d'] + 1, 'd', CUT, parts=[lid])
    return body, lid


def build_mockup(root, p, g):
    # Dokumen Part Design hanya boleh satu komponen: mockup = body transparan berawalan "Mockup".
    c = root
    items = []

    def add(name, f):
        b = f.bodies.item(0)
        b.name = 'Mockup ' + name
        b.opacity = 0.45
        items.append(b)

    oh0, oh1 = g['oled_h0'], g['oled_h1']
    glass_top = oh1 - p['oled_glass_from_top']
    add('OLED kaca', box(c, -26.7 / 2, 26.7 / 2, glass_top - 19.26, glass_top, g['d_oled0'], g['d_oled0'] + 1.85, 'd', NEW))
    add('OLED PCB', box(c, -p['oled_w'] / 2, p['oled_w'] / 2, oh0, oh1, g['d_oled0'] + 1.85, g['d_oled0'] + 1.85 + 1.2, 'd', NEW))
    L, F = g['bL'], g['bF']
    add('Super Mini PCB', box(c, g['smL'], g['bR'], F, F + p['sm_w'], g['d_sm0'], g['d_sm0'] + p['pcb_t'], 'd', NEW))
    add('Super Mini USB-C', box(c, g['bR'] - 6.8, g['bR'] + 0.5, g['sm_usb_h'] - 4.47, g['sm_usb_h'] + 4.47,
                                g['d_sm0'] + p['pcb_t'], g['d_sm0'] + p['pcb_t'] + p['usbc_t'], 'd', NEW))
    add('TP4056 PCB', box(c, L, L + p['tp_w'], F, F + p['tp_h'], g['d_tp0'], g['d_tp0'] + p['pcb_t'], 'd', NEW))
    add('TP4056 USB-C', box(c, g['tp_usb_w'] - 4.47, g['tp_usb_w'] + 4.47, F, F + 7.3,
                            g['d_tp0'] + p['pcb_t'], g['d_tp0'] + p['pcb_t'] + p['usbc_t'], 'd', NEW))
    add('LiPo 102530', box(c, -12.5, 12.5, F, F + 30.0, g['d_bat0'], g['d_bat0'] + 10.0, 'd', NEW))
    Lw = g['inL']
    add('Saklar', box(c, Lw + 0.1, Lw + 0.1 + p['sw_h'], g['sw_h0'], g['sw_h0'] + p['sw_len'],
                      g['sw_dc'] - p['sw_thk'] / 2, g['sw_dc'] + p['sw_thk'] / 2, 'w', NEW))
    add('Tuas saklar', box(c, Lw - p['wall'] - 0.3, Lw + 0.1, g['sw_hc'] - 0.8 - 0.9, g['sw_hc'] + 0.8 - 0.9,
                           g['sw_dc'] - 0.75, g['sw_dc'] + 0.75, 'w', NEW))
    add('Buzzer', cyl(c, 'w', g['bz_w'], g['bz_h'], g['bz_d'], p['bz_d'], p['bz_h'], NEW))
    add('Sensor sentuh', box(c, -p['touch_w'] / 2, p['touch_w'] / 2, g['ceil'] + p['touch_pocket'] - 2.2,
                             g['ceil'] + p['touch_pocket'], g['touch_dc'] - p['touch_d'] / 2,
                             g['touch_dc'] + p['touch_d'] / 2, 'h', NEW))
    return items


def apply_appearance(app, design, bodies):
    # Filament: eSUN PETG Translucent Pink
    name = 'PETG eSUN Translucent Pink'
    ap = design.appearances.itemByName(name)
    if not ap:
        src = app.materialLibraries.itemByName('Fusion Appearance Library') \
            .appearances.itemByName('Plastic - Translucent Glossy (Red)')
        ap = design.appearances.addByCopy(src, name)
    pink = adsk.core.Color.create(244, 120, 170, 255)
    white = adsk.core.Color.create(255, 255, 255, 255)
    for pid, col in (('opaque_albedo', pink), ('opaque_mfp_modifier', pink),
                     ('surface_albedo', white), ('opaque_luminance_modifier', white)):
        prop = adsk.core.ColorProperty.cast(ap.appearanceProperties.itemById(pid))
        if prop:
            prop.value = col
    for b in bodies:
        b.appearance = ap


def run(_context: str):
    app = adsk.core.Application.get()
    design = adsk.fusion.Design.cast(app.activeProduct)
    root = design.rootComponent
    if design.timeline.count:                 # jalankan ulang = bangun dari nol
        design.timeline.moveToBeginning()
        design.timeline.deleteAllAfterMarker()
    g = geometry(P)
    body, lid = build_case(root, P, g)
    items = build_mockup(root, P, g)
    apply_appearance(app, design, (body, lid))
    print('Ukuran luar badan+tutup: %.1f x %.1f x %.1f mm (L x T x D), kuping +%.1f mm'
          % (g['out_w'], g['out_h'], g['out_d'], P['lug_h']))
    print('Rongga dalam: %.1f x %.1f mm' % (g['in_w'], g['in_h']))
    print('Pusat jendela dari alas: %.1f mm' % g['win_hc'])
    print('Badan valid:', body.isSolid, ' Tutup valid:', lid.isSolid, ' Mockup:', len(items))
