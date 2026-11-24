package io.github.taicicaks01.lokana

import android.app.Notification
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Icon
import android.os.Handler
import android.os.Looper
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.Calendar

/**
 * Navigasi Google Maps -> NAV (v0.6, parser versi pertama).
 *
 * Dibentuk dari notifikasi asli Maps di HP Wayan (Android 16, bahasa Indonesia, ProgressStyle):
 *   title    = "Ambil arah menuju Jl. Raya Anturan"   (instruksi + jalan; saat bergerak mungkin diawali jarak)
 *   subText  = "Tiba 01.02"                          (jam tiba)
 *   android.shortCriticalText                        (kosong saat diam; dugaan: jarak saat mendekat)
 *   smallIcon 132x132 panah putih + alpha, largeIcon 94x94 panah biru
 * Jarak saat bergerak belum terlihat (perlu rekaman perjalanan, NavCapture) -> dicari di beberapa tempat,
 * kalau tidak ketemu dikirim "tidak diketahui".
 *
 * Hanya mengirim saat isi berubah, ditambah ulang tiap 20 dtk (Lokana menganggap berhenti setelah 3 menit,
 * dan supaya Lokana yang baru tersambung lagi langsung dapat data). Notifikasi hilang -> NAV state 1.
 */
object NavForwarder {
    private const val TAG = "LokanaNav"
    private const val RESEND_MS = 20_000L
    private val main = Handler(Looper.getMainLooper())
    private var lastPayload: ByteArray? = null
    private var activeKey: String? = null

    private val resend = object : Runnable {
        override fun run() {
            val p = lastPayload ?: return
            if (BleLink.state == BleLink.State.READY) BleLink.send(Proto.T_NAV, p, false) {}
            main.postDelayed(this, RESEND_MS)
        }
    }

    private fun isNav(sbn: StatusBarNotification) =
        sbn.packageName == NavCapture.MAPS && sbn.notification.category == Notification.CATEGORY_NAVIGATION

    fun onPosted(ctx: Context, sbn: StatusBarNotification) {
        if (!isNav(sbn) || !NotifPrefs.nav(ctx)) return
        val n = sbn.notification
        val ex = n.extras
        val title = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty().trim()
        val text = ex.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty().trim()
        val sub = ex.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString().orEmpty().trim()
        val critical = ex.getCharSequence("android.shortCriticalText")?.toString().orEmpty().trim()

        val p = parse(title, text, sub, critical)
        val (w, h, bits) = icon(ctx, n)
        val payload = Proto.nav(p.distM, Proto.toAscii(p.distText, 15), Proto.toAscii(p.instr, 63),
            Proto.toAscii(p.street, 63), p.etaMin, w, h, bits, Proto.toAscii(p.etaText, 15))
        activeKey = sbn.key
        if (lastPayload?.contentEquals(payload) == true) return
        lastPayload = payload
        // Tanpa instruksi & nama jalan (lokasi pengguna tidak ditulis ke logcat)
        Log.i(TAG, "NAV jarak=${p.distM} m, eta=${p.etaMin} mnt, ikon=${w}x$h")
        if (BleLink.state == BleLink.State.READY) BleLink.send(Proto.T_NAV, payload, false) {}
        main.removeCallbacks(resend)
        main.postDelayed(resend, RESEND_MS)
    }

    fun onRemoved(sbn: StatusBarNotification) {
        if (sbn.key != activeKey) return
        activeKey = null
        lastPayload = null
        main.removeCallbacks(resend)
        if (BleLink.state == BleLink.State.READY) BleLink.send(Proto.T_NAV, Proto.navStop(), true) {}
    }

    /** Pengguna mematikan "Navigasi Google Maps" di aplikasi: tutup layar Navigasi di Lokana. */
    fun disable() {
        if (activeKey == null) return
        activeKey = null
        lastPayload = null
        main.removeCallbacks(resend)
        if (BleLink.state == BleLink.State.READY) BleLink.send(Proto.T_NAV, Proto.navStop(), true) {}
    }

    // ---------------- Teks ----------------
    data class Parsed(val distM: Long, val distText: String, val instr: String, val street: String,
                      val etaMin: Int, val etaText: String)

    private val DIST = Regex("""^(\d+(?:[.,]\d+)?)\s*(km|m|mi|ft|mil|kaki)\b\.?""", RegexOption.IGNORE_CASE)
    private val SEP = Regex("""^[\s\-–—·•,:]+""")
    // Kata penghubung pertama: "Belok kanan ke Jl. X", "Ambil arah menuju Jl. X", "Turn right onto X"
    private val SPLIT = Regex("""^(.+?)\s+(menuju|ke arah|ke|di|pada|toward|towards|onto|on|to)\s+(.+)$""",
        RegexOption.IGNORE_CASE)
    private val CLOCK = Regex("""(\d{1,2})[.:](\d{2})""")

    // Maps memakai spasi tak terputus (U+00A0 / U+202F) di "2,9 km"
    private fun clean(s: String) = s.replace(' ', ' ').replace(' ', ' ').trim()

    /**
     * Saat bergerak (data asli 2026-11-24): title "2,9 km · Belok kiri ke Jl. Damai/Jl. I Gede Taman",
     * shortCriticalText "2,9 km", subText "Tiba 01.39". Saat diam: title tanpa jarak ("Ambil arah menuju ...").
     */
    fun parse(title0: String, text0: String, sub0: String, critical0: String): Parsed {
        val title = clean(title0); val text = clean(text0); val sub = clean(sub0); val critical = clean(critical0)
        var distText = DIST.find(critical)?.value ?: ""
        var rest = title
        // Jarak di awal judul selalu dibuang dari kalimat instruksi
        DIST.find(title)?.let { if (distText.isEmpty()) distText = it.value; rest = title.substring(it.range.last + 1) }
        var sentence = rest.replace(SEP, "").trim()
        if (distText.isEmpty()) DIST.find(text)?.let { distText = it.value }
        if (sentence.isEmpty()) sentence = text.replace(DIST, "").replace(SEP, "").trim()

        val m = SPLIT.find(sentence)
        val instr = m?.groupValues?.get(1)?.trim() ?: sentence
        val street = m?.groupValues?.get(3)?.trim() ?: ""

        return Parsed(meters(distText), distText.trim(), instr, street, etaMinutes(sub), sub)
    }

    private fun meters(d: String): Long {
        val m = DIST.find(d) ?: return -1
        val v = m.groupValues[1].replace(',', '.').toDoubleOrNull() ?: return -1
        return when (m.groupValues[2].lowercase()) {
            "km" -> (v * 1000).toLong()
            "mi", "mil" -> (v * 1609.34).toLong()
            "ft", "kaki" -> (v * 0.3048).toLong()
            else -> v.toLong()
        }
    }

    /** "Tiba 01.02" -> menit dari sekarang (lewat tengah malam ditambah 24 jam). -1 kalau tidak ada jam. */
    private fun etaMinutes(sub: String): Int {
        val m = CLOCK.find(sub) ?: return -1
        val h = m.groupValues[1].toInt(); val min = m.groupValues[2].toInt()
        if (h > 23 || min > 59) return -1
        val now = Calendar.getInstance()
        var diff = (h * 60 + min) - (now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE))
        if (diff < 0) diff += 24 * 60
        return diff
    }

    // ---------------- Ikon panah -> 1-bit 32x32 ----------------
    // smallIcon panah putih + alpha (paling bersih) hanya kalau berupa bitmap; versi Maps lain bisa memakai
    // resource logo Maps di smallIcon -> pakai largeIcon (panah berwarna, latar transparan).
    private fun icon(ctx: Context, n: Notification): Triple<Int, Int, ByteArray> {
        val small = n.smallIcon?.takeIf { it.type == Icon.TYPE_BITMAP || it.type == Icon.TYPE_ADAPTIVE_BITMAP }
        val src = small ?: n.getLargeIcon() ?: return Triple(0, 0, ByteArray(0))
        val bmp = toBitmap(ctx, src) ?: return Triple(0, 0, ByteArray(0))
        return Triple(32, 32, to1Bit(bmp))
    }

    private fun toBitmap(ctx: Context, icon: Icon): Bitmap? = try {
        val d = icon.loadDrawable(ctx)
        (d as? BitmapDrawable)?.bitmap ?: d?.let {
            val w = it.intrinsicWidth.coerceIn(1, 256); val h = it.intrinsicHeight.coerceIn(1, 256)
            Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).also { b ->
                val c = Canvas(b); it.setBounds(0, 0, w, h); it.draw(c)
            }
        }
    } catch (e: Exception) { Log.w(TAG, "ikon tidak terbaca", e); null }

    /** Skala ke 32x32 (rasio dijaga, di tengah), lalu 1-bit: dari alpha kalau latar transparan, kalau tidak dari kontras. */
    fun to1Bit(src: Bitmap): ByteArray {
        val s = 32f / maxOf(src.width, src.height)
        val w = maxOf(1, (src.width * s).toInt()); val h = maxOf(1, (src.height * s).toInt())
        val small = Bitmap.createScaledBitmap(src, w, h, true)
        val corner = src.getPixel(0, 0)
        val transparentBg = (corner ushr 24) < 128
        val bgLum = lum(corner)
        val out = ByteArray(4 * 32)
        val ox = (32 - w) / 2; val oy = (32 - h) / 2
        for (y in 0 until h) for (x in 0 until w) {
            val c = small.getPixel(x, y)
            val on = if (transparentBg) (c ushr 24) >= 128 else kotlin.math.abs(lum(c) - bgLum) > 64
            if (on) { val px = x + ox; val py = y + oy; out[py * 4 + px / 8] = (out[py * 4 + px / 8].toInt() or (0x80 ushr (px % 8))).toByte() }
        }
        return out
    }

    private fun lum(c: Int) = ((c shr 16 and 0xFF) * 3 + (c shr 8 and 0xFF) * 6 + (c and 0xFF)) / 10
}
