package io.github.taicicaks01.lokana

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Pengingat ketinggalan: HP berbunyi jika Lokana tertinggal.
 *
 * Dianggap tertinggal jika koneksi yang sudah siap putus karena sinyal hilang (status GATT 8, timeout),
 * bukan diputus pengguna/Lokana, lalu tidak tersambung lagi dalam [delayS] detik. RSSI terakhir yang
 * masih kuat (≥ −70 dBm) berarti Lokana dimatikan di dekat HP: cukup notifikasi tanpa bunyi.
 * Setelan disimpan aplikasi Flutter di SharedPreferences "lokana_app" (string): leave_on, leave_delay,
 * leave_mode ("alarm" / "notif"), leave_snooze (epoch ms).
 */
object LeaveAlert {
    private const val TAG = "LokanaLeave"
    private const val NOTIF_ID = 3
    private const val GATT_CONN_TIMEOUT = 8
    private const val NEAR_RSSI = -70
    private const val RSSI_MAX_AGE_MS = 6000L
    private const val RING_MS = 20000L

    private val main = Handler(Looper.getMainLooper())
    private var pending: Runnable? = null
    private var wake: PowerManager.WakeLock? = null
    private var showing = false

    private fun prefs(ctx: Context) = ctx.applicationContext.getSharedPreferences("lokana_app", Context.MODE_PRIVATE)
    private fun enabled(ctx: Context) = prefs(ctx).getString("leave_on", "1") != "0"
    private fun delayS(ctx: Context) = (prefs(ctx).getString("leave_delay", null)?.toIntOrNull() ?: 20).coerceIn(5, 300)
    private fun loud(ctx: Context) = prefs(ctx).getString("leave_mode", "alarm") != "notif"
    fun snoozeUntil(ctx: Context) = prefs(ctx).getString("leave_snooze", null)?.toLongOrNull() ?: 0L

    /** Jeda pengingat [minutes] menit; 0 = lanjutkan sekarang. */
    fun snooze(ctx: Context, minutes: Int) {
        val until = if (minutes > 0) System.currentTimeMillis() + minutes * 60_000L else 0L
        prefs(ctx).edit().putString("leave_snooze", until.toString()).apply()
        cancel(ctx)
    }

    /** Koneksi siap ke Lokana putus tanpa diminta pengguna. [rssiAgeMs] umur RSSI terakhir. */
    fun lost(ctx: Context, status: Int, rssi: Int?, rssiAgeMs: Long) {
        val app = ctx.applicationContext
        cancelPending()
        val near = rssi != null && rssiAgeMs <= RSSI_MAX_AGE_MS && rssi >= NEAR_RSSI
        val why = when {
            !enabled(app) -> "mati"
            System.currentTimeMillis() < snoozeUntil(app) -> "dijeda"
            status != GATT_CONN_TIMEOUT -> "diputus (status $status)"
            else -> null
        }
        Log.i(TAG, "Lokana hilang: status=$status rssi=$rssi (${rssiAgeMs} ms) -> ${why ?: "tunggu ${delayS(app)} dtk"}")
        if (why != null) return
        val d = delayS(app)
        acquireWake(app, d * 1000L + 5000)
        val r = Runnable {
            pending = null
            releaseWake()
            if (BleLink.state != BleLink.State.READY) fire(app, soft = near, test = false)
        }
        pending = r
        main.postDelayed(r, d * 1000L)
    }

    /** Lokana tersambung lagi: batalkan yang menunggu, tutup pengingat. */
    fun back(ctx: Context) {
        cancelPending()
        if (showing) cancel(ctx)
    }

    /** Pengguna memutus / melupakan Lokana. */
    fun cancel(ctx: Context) {
        cancelPending()
        showing = false
        Alarm.stopLeave(ctx)
        (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIF_ID)
    }

    /** Tombol "Coba" di aplikasi: pengingat penuh selama 4 detik. */
    fun test(ctx: Context) = fire(ctx.applicationContext, soft = false, test = true)

    private fun fire(app: Context, soft: Boolean, test: Boolean) {
        showing = true
        val ring = !soft && loud(app)
        if (ring) Alarm.startLeave(app, if (test) 4000L else RING_MS) else Alarm.buzz(app)
        notify(app, soft, ring, test)
    }

    private fun notify(app: Context, soft: Boolean, ring: Boolean, test: Boolean) {
        LinkService.ensureChannels(app)
        fun svc(action: String, code: Int) = PendingIntent.getService(app, code,
            Intent(app, LinkService::class.java).setAction(action),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val open = PendingIntent.getActivity(app, 5,
            Intent(app, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val time = SimpleDateFormat("HH.mm", Locale.getDefault()).format(Date())
        val title = if (soft) "Lokana terputus" else "Lokana tertinggal?"
        val text = when {
            test -> "Ini contoh pengingat. Begini rasanya kalau Lokana tertinggal."
            soft -> "Pukul $time. Sinyal terakhir masih kuat, mungkin Lokana dimatikan di dekat HP."
            else -> "Pukul $time sambungan hilang saat Lokana menjauh. Cek tempat terakhir kamu bersamanya."
        }
        val b = NotificationCompat.Builder(app, LinkService.CH_LEAVE)
            .setSmallIcon(R.drawable.ic_stat_lokana)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setPriority(if (soft) NotificationCompat.PRIORITY_DEFAULT else NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setContentIntent(open)
            .setAutoCancel(true)
            .setDeleteIntent(svc(LinkService.ACTION_LEAVE_STOP, 6))
        if (ring) b.addAction(0, "Matikan", svc(LinkService.ACTION_LEAVE_STOP, 7))
        if (!test) b.addAction(0, "Jeda 1 jam", svc(LinkService.ACTION_LEAVE_SNOOZE, 8))
        try {
            (app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIF_ID, b.build())
        } catch (e: SecurityException) {
            Log.w(TAG, "izin notifikasi belum diberikan", e)
        }
    }

    private fun cancelPending() {
        pending?.let { main.removeCallbacks(it) }
        pending = null
        releaseWake()
    }

    // Jeda menunggu harus tetap berjalan walau layar HP mati (Doze)
    private fun acquireWake(app: Context, ms: Long) {
        releaseWake()
        wake = (app.getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "lokana:leave").apply { acquire(ms) }
    }

    private fun releaseWake() {
        wake?.let { if (it.isHeld) it.release() }
        wake = null
    }
}
