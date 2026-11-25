"""Susunan tampilan Monitor dari pengaturan Desktop (v0.8 langkah 2): label sendiri, format angka, dua metrik per baris.

Dipakai bersama oleh pekerja (yang mengirim ke Lokana) dan jendela pengaturan (pratinjau), jadi keduanya selalu sama.

Config:
  "metrics":  ["cpu", "cpu_temp", ...]   urutan metrik yang tampil
  "labels":   {"cpu": "Prosesor"}        label sendiri, maks 10 huruf (kosong = bawaan)
  "decimals": {"down": 2}                "auto" (bawaan) / 0 / 1 / 2
  "pairs":    ["cpu"]                    metrik yang digabung dengan metrik berikutnya dalam satu baris
  "decimal_sep": ","                     "," (bawaan, gaya Indonesia) atau "."
"""
from sensors import MAX_METRICS

LABEL_MAX = 10
TEXT_MAX = 11
DEGREE = "°"


def clean_label(s):
    """Label ASCII yang bisa digambar font Lokana (plus derajat), maks 10 huruf."""
    out = "".join(ch for ch in s if 32 <= ord(ch) < 127 or ch == DEGREE)
    return out[:LABEL_MAX]


def value_text(metric, decimals="auto", sep=","):
    """Teks nilai siap tampil: "34%", "61°C", "1,25MB/s". Desimal "auto" = sama dengan aturan firmware."""
    kind, _label, value, unit = metric
    if decimals == "auto":
        d = 0 if kind in (1, 2) or abs(value) >= 100 else 1
    else:
        d = max(0, min(2, int(decimals)))
    num = "%.*f" % (d, value)
    if sep == ",":
        num = num.replace(".", ",")
    text = num + (DEGREE + "C" if kind == 2 else unit)
    return text[:TEXT_MAX]


def build(values, cfg):
    """values: {id: (kind, label, value, unit) | None} dari Sensors.read_all().
    Hasil: (ids, metrics, texts, rows) siap PC_STATS; rows = [(a, b|None)]."""
    labels = cfg.get("labels") or {}
    decimals = cfg.get("decimals") or {}
    pairs = set(cfg.get("pairs") or [])
    sep = cfg.get("decimal_sep", ",")
    ids, metrics, texts = [], [], []
    for mid in cfg.get("metrics") or []:
        m = values.get(mid)
        if m is None:
            continue
        kind, label, value, unit = m
        own = clean_label(labels.get(mid, ""))
        if own:
            # baterai: tanda "+" (sedang mengisi) tetap ikut walau label diganti
            label = (own + "+")[:LABEL_MAX] if label.endswith("+") and not own.endswith("+") else own
        ids.append(mid)
        metrics.append((kind, label, value, unit))
        texts.append(value_text(m, decimals.get(mid, "auto"), sep))
        if len(ids) >= MAX_METRICS:
            break
    rows, i = [], 0
    while i < len(ids):
        if ids[i] in pairs and i + 1 < len(ids):
            rows.append((i, i + 1))
            i += 2
        else:
            rows.append((i, None))
            i += 1
    return ids, metrics, texts, rows
