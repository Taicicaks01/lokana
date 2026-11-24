package io.github.taicicaks01.lokana

import android.app.Notification
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Icon
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONObject
import java.io.File

/**
 * Alat pengembangan (v0.6): rekam notifikasi navigasi Google Maps untuk membuat parser NAV dari data asli.
 *
 * Hanya aktif kalau file `Android/data/<paket>/files/nav_capture/ON` ada (dibuat lewat adb), jadi pengguna biasa
 * tidak pernah merekam apa pun. Semua tersimpan di HP sendiri, tidak dikirim ke mana pun:
 *   log.jsonl   satu baris per pembaruan notifikasi (teks + semua extras berbentuk teks/angka)
 *   icon_N.png  ikon panah (largeIcon / smallIcon) setiap kali gambarnya berubah
 * Ambil dengan: adb pull /sdcard/Android/data/io.github.taicicaks01.lokana/files/nav_capture
 */
object NavCapture {
    private const val TAG = "LokanaNavCap"
    const val MAPS = "com.google.android.apps.maps"
    private const val MAX_ICONS = 400
    private var lastLine = ""
    private val iconHashes = HashMap<Int, String>()
    private var iconCount = -1

    private fun dir(ctx: Context): File? = ctx.getExternalFilesDir(null)?.let { File(it, "nav_capture") }

    fun enabled(ctx: Context): Boolean = dir(ctx)?.let { File(it, "ON").exists() } == true

    fun record(ctx: Context, sbn: StatusBarNotification, removed: Boolean = false) {
        if (sbn.packageName != MAPS || !enabled(ctx)) return
        try {
            val d = dir(ctx) ?: return
            val n = sbn.notification
            val ex = n.extras
            val o = JSONObject()
            o.put("t", System.currentTimeMillis())
            o.put("removed", removed)
            o.put("id", sbn.id)
            o.put("category", n.category ?: "")
            o.put("flags", n.flags)
            val extras = JSONObject()
            for (k in ex.keySet()) {
                val v = ex.get(k) ?: continue
                if (v is CharSequence || v is Number || v is Boolean || v is String) extras.put(k, v.toString().take(300))
                else if (v is Icon || v is Bitmap) extras.put(k, v.javaClass.simpleName)
                else extras.put(k, v.javaClass.simpleName + ": " + v.toString().take(200))
            }
            o.put("extras", extras)
            if (!removed) {
                o.put("largeIcon", saveIcon(ctx, d, n.getLargeIcon()))
                o.put("smallIcon", saveIcon(ctx, d, n.smallIcon))
            }
            val line = o.toString()
            // Lewati pembaruan yang sama persis (selain waktu)
            val key = line.substringAfter(",\"removed\"")
            if (key == lastLine) return
            lastLine = key
            File(d, "log.jsonl").appendText(line + "\n")
        } catch (e: Exception) {
            Log.w(TAG, "rekam gagal", e)
        }
    }

    private fun saveIcon(ctx: Context, d: File, icon: Icon?): String {
        if (icon == null) return ""
        val dr = icon.loadDrawable(ctx) ?: return ""
        val bmp = (dr as? BitmapDrawable)?.bitmap ?: run {
            val w = dr.intrinsicWidth.coerceIn(1, 256)
            val h = dr.intrinsicHeight.coerceIn(1, 256)
            Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).also {
                val c = Canvas(it); dr.setBounds(0, 0, w, h); dr.draw(c)
            }
        }
        val px = IntArray(bmp.width * bmp.height)
        bmp.getPixels(px, 0, bmp.width, 0, 0, bmp.width, bmp.height)
        val h = px.contentHashCode() * 31 + bmp.width
        iconHashes[h]?.let { return it }
        if (iconCount < 0) iconCount = d.listFiles { f -> f.name.startsWith("icon_") }?.size ?: 0
        if (iconCount >= MAX_ICONS) return "penuh"
        val name = "icon_${iconCount++}_${bmp.width}x${bmp.height}.png"
        File(d, name).outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
        iconHashes[h] = name
        return name
    }
}
