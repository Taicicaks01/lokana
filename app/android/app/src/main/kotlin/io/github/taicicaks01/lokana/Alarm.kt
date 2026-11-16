package io.github.taicicaks01.lokana

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Cari HP (FIND_PHONE): bunyi alarm keras + getar + notifikasi dengan tombol "Ketemu".
 * Memakai stream alarm supaya tetap terdengar saat HP dalam mode senyap.
 * Volume alarm dinaikkan sementara lalu dikembalikan.
 */
object Alarm {
    private const val TAG = "LokanaAlarm"
    private const val NOTIF_ID = 2
    private const val MAX_MS = 60000L          // pengaman: berhenti sendiri setelah 60 detik

    private var player: MediaPlayer? = null
    private var savedVolume = -1
    private val main = Handler(Looper.getMainLooper())
    var ringing = false; private set

    fun start(ctx: Context) {
        if (ringing) return
        ringing = true
        val app = ctx.applicationContext
        val am = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        savedVolume = am.getStreamVolume(AudioManager.STREAM_ALARM)
        am.setStreamVolume(AudioManager.STREAM_ALARM, am.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0)
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        try {
            player = MediaPlayer().apply {
                setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                setDataSource(app, uri)
                isLooping = true
                prepare()
                start()
            }
        } catch (e: Exception) {
            Log.w(TAG, "alarm tidak bisa diputar", e)
        }
        vibrator(app)?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 600, 400), 0))
        showNotification(app)
        main.removeCallbacksAndMessages(null)
        main.postDelayed({ stop(app) }, MAX_MS)
    }

    fun stop(ctx: Context) {
        if (!ringing) return
        ringing = false
        val app = ctx.applicationContext
        main.removeCallbacksAndMessages(null)
        player?.let { try { it.stop(); it.release() } catch (_: Exception) {} }
        player = null
        vibrator(app)?.cancel()
        if (savedVolume >= 0) {
            (app.getSystemService(Context.AUDIO_SERVICE) as AudioManager)
                .setStreamVolume(AudioManager.STREAM_ALARM, savedVolume, 0)
            savedVolume = -1
        }
        (app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIF_ID)
    }

    private fun vibrator(app: Context): Vibrator? =
        if (Build.VERSION.SDK_INT >= 31) (app.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        else @Suppress("DEPRECATION") (app.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator)

    private fun showNotification(app: Context) {
        LinkService.ensureChannels(app)
        val found = PendingIntent.getService(app, 1,
            Intent(app, LinkService::class.java).setAction(LinkService.ACTION_PHONE_FOUND),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val open = PendingIntent.getActivity(app, 2,
            Intent(app, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = NotificationCompat.Builder(app, LinkService.CH_ALARM)
            .setSmallIcon(R.drawable.ic_stat_lokana)
            .setContentTitle("Lokana memanggil HP ini")
            .setContentText("Ketuk \"Ketemu\" untuk menghentikan bunyi")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(0, "Ketemu", found)
            .build()
        try {
            (app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIF_ID, n)
        } catch (e: SecurityException) {
            Log.w(TAG, "izin notifikasi belum diberikan", e)
        }
    }
}
