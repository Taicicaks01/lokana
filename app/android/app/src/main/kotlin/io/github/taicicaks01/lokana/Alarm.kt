package io.github.taicicaks01.lokana

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.provider.OpenableColumns
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
 * Nada bisa dipilih pengguna (Pengaturan aplikasi): nada sistem atau file audio sendiri.
 */
object Alarm {
    private const val TAG = "LokanaAlarm"
    private const val NOTIF_ID = 2
    private const val MAX_MS = 60000L          // pengaman: berhenti sendiri setelah 60 detik

    private var player: MediaPlayer? = null
    private var savedVolume = -1
    private val main = Handler(Looper.getMainLooper())
    var ringing = false; private set
    private var preview: MediaPlayer? = null
    private val previewStop = Runnable { stopPreview() }

    private const val PREF_SOUND = "find_ringtone"   // URI (string) di SharedPreferences "lokana_app"

    private fun defaultUri(): Uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)

    private fun prefs(ctx: Context) = ctx.applicationContext.getSharedPreferences("lokana_app", Context.MODE_PRIVATE)

    /** Nada pilihan pengguna, null = bawaan (alarm HP). */
    fun customUri(ctx: Context): Uri? = prefs(ctx).getString(PREF_SOUND, null)?.takeIf { it.isNotEmpty() }?.let(Uri::parse)

    fun setSound(ctx: Context, uri: Uri?) {
        prefs(ctx).edit().putString(PREF_SOUND, uri?.toString() ?: "").apply()
    }

    /** Nama nada untuk ditampilkan di aplikasi. */
    fun soundTitle(ctx: Context): String {
        val uri = customUri(ctx) ?: return "Bawaan (alarm HP)"
        return try {
            if (uri.scheme == "content" && uri.authority != "settings" && uri.authority != "media") {
                ctx.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                    if (c.moveToFirst()) c.getString(0) else null
                }
            } else null
        } catch (_: Exception) { null }
            ?: RingtoneManager.getRingtone(ctx, uri)?.getTitle(ctx)
            ?: "Nada pilihan"
    }

    private fun newPlayer(app: Context, uri: Uri, loop: Boolean): MediaPlayer = MediaPlayer().apply {
        setAudioAttributes(AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
        setDataSource(app, uri)
        isLooping = loop
        prepare()
        start()
    }

    /** Nada pilihan; kalau file sudah dihapus / izin hilang, kembali ke nada bawaan. */
    private fun play(app: Context, loop: Boolean): MediaPlayer? {
        customUri(app)?.let { u ->
            try { return newPlayer(app, u, loop) } catch (e: Exception) { Log.w(TAG, "nada pilihan gagal, pakai bawaan", e) }
        }
        return try { newPlayer(app, defaultUri(), loop) } catch (e: Exception) { Log.w(TAG, "alarm tidak bisa diputar", e); null }
    }

    /** Coba nada 4 detik dengan volume alarm saat ini. */
    fun preview(ctx: Context) {
        if (ringing) return
        stopPreview()
        val app = ctx.applicationContext
        preview = play(app, false)
        main.removeCallbacks(previewStop)
        main.postDelayed(previewStop, 4000)
    }

    fun stopPreview() {
        preview?.let { try { it.stop(); it.release() } catch (_: Exception) {} }
        preview = null
    }

    // Bunyi keras + getar (dipakai Cari HP dan pengingat ketinggalan)
    private fun beginSound(app: Context) {
        val am = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (savedVolume < 0) savedVolume = am.getStreamVolume(AudioManager.STREAM_ALARM)
        am.setStreamVolume(AudioManager.STREAM_ALARM, am.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0)
        stopPreview()
        player?.let { try { it.stop(); it.release() } catch (_: Exception) {} }
        player = play(app, true)
        vibrator(app)?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 600, 400), 0))
    }

    private fun endSound(app: Context) {
        player?.let { try { it.stop(); it.release() } catch (_: Exception) {} }
        player = null
        vibrator(app)?.cancel()
        if (savedVolume >= 0) {
            (app.getSystemService(Context.AUDIO_SERVICE) as AudioManager)
                .setStreamVolume(AudioManager.STREAM_ALARM, savedVolume, 0)
            savedVolume = -1
        }
    }

    private val findTimeout = Runnable { stop(appCtx ?: return@Runnable) }
    private val leaveTimeout = Runnable { stopLeave(appCtx ?: return@Runnable) }
    private var appCtx: Context? = null
    private var leaveRinging = false

    fun start(ctx: Context) {
        if (ringing) return
        val app = ctx.applicationContext
        appCtx = app
        if (leaveRinging) { leaveRinging = false; main.removeCallbacks(leaveTimeout) }   // Cari HP lebih penting
        ringing = true
        beginSound(app)
        showNotification(app)
        main.removeCallbacks(findTimeout)
        main.postDelayed(findTimeout, MAX_MS)
    }

    fun stop(ctx: Context) {
        if (!ringing) return
        ringing = false
        val app = ctx.applicationContext
        main.removeCallbacks(findTimeout)
        endSound(app)
        (app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIF_ID)
    }

    /** Pengingat ketinggalan: bunyi [ms] milidetik (notifikasinya diatur [LeaveAlert]). */
    fun startLeave(ctx: Context, ms: Long) {
        if (ringing) return
        val app = ctx.applicationContext
        appCtx = app
        leaveRinging = true
        beginSound(app)
        main.removeCallbacks(leaveTimeout)
        main.postDelayed(leaveTimeout, ms)
    }

    fun stopLeave(ctx: Context) {
        main.removeCallbacks(leaveTimeout)
        if (!leaveRinging) return
        leaveRinging = false
        endSound(ctx.applicationContext)
    }

    /** Getar singkat (pengingat tanpa bunyi). */
    fun buzz(ctx: Context) {
        vibrator(ctx.applicationContext)?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 300, 200, 300), -1))
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
