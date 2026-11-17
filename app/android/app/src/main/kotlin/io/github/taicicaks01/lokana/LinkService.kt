package io.github.taicicaks01.lokana

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Foreground service yang menjaga proses aplikasi tetap hidup selama Lokana tersambung,
 * supaya koneksi BLE dan Cari HP tetap jalan saat aplikasi ditutup / layar HP mati.
 * Koneksinya sendiri ada di [BleLink].
 */
class LinkService : Service() {
    companion object {
        private const val TAG = "LokanaService"
        const val CH_LINK = "link"
        const val CH_ALARM = "find_phone"
        const val ACTION_PHONE_FOUND = "lokana.PHONE_FOUND"
        const val ACTION_DISCONNECT = "lokana.DISCONNECT"
        const val CH_LEAVE = "leave_alert"
        const val ACTION_LEAVE_STOP = "lokana.LEAVE_STOP"
        const val ACTION_LEAVE_SNOOZE = "lokana.LEAVE_SNOOZE"
        private const val NOTIF_ID = 1

        fun start(ctx: Context) {
            try {
                ContextCompat.startForegroundService(ctx, Intent(ctx, LinkService::class.java))
            } catch (e: Exception) {
                Log.w(TAG, "foreground service tidak bisa dimulai", e)
            }
        }

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, LinkService::class.java))
        }

        fun ensureChannels(ctx: Context) {
            if (Build.VERSION.SDK_INT < 26) return
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(NotificationChannel(CH_LINK, "Koneksi Lokana",
                NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) })
            nm.createNotificationChannel(NotificationChannel(CH_ALARM, "Cari HP",
                NotificationManager.IMPORTANCE_HIGH).apply { setSound(null, null) })
            // Bunyi & getar diatur aplikasi (Alarm), saluran ini hanya untuk tampilan
            nm.createNotificationChannel(NotificationChannel(CH_LEAVE, "Pengingat ketinggalan",
                NotificationManager.IMPORTANCE_HIGH).apply { setSound(null, null); enableVibration(false) })
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        BleLink.init(this)
        when (intent?.action) {
            ACTION_PHONE_FOUND -> { BleLink.phoneFound(); return START_STICKY }
            ACTION_DISCONNECT -> { BleLink.disconnect(forget = false); return START_NOT_STICKY }
            ACTION_LEAVE_STOP -> { LeaveAlert.cancel(this); return START_STICKY }
            ACTION_LEAVE_SNOOZE -> { LeaveAlert.snooze(this, 60); return START_STICKY }
        }
        // Dihidupkan ulang sistem setelah proses dimatikan (START_STICKY): sambung lagi ke Lokana terakhir
        if (intent == null) BleLink.resume()
        ensureChannels(this)
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE)
        val off = PendingIntent.getService(this, 3,
            Intent(this, LinkService::class.java).setAction(ACTION_DISCONNECT), PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(this, CH_LINK)
            .setSmallIcon(R.drawable.ic_stat_lokana)
            .setColor(ContextCompat.getColor(this, R.color.lokana_pink))
            .setContentTitle("Lokana")
            .setContentText("Menjaga koneksi dengan Lokana")
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(0, "Putuskan", off)
            .build()
        val type = if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE else 0
        try {
            ServiceCompat.startForeground(this, NOTIF_ID, n, type)
        } catch (e: Exception) {
            Log.w(TAG, "startForeground gagal", e)
            stopSelf()
        }
        return START_STICKY
    }
}
