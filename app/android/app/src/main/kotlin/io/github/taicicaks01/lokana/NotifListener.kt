package io.github.taicicaks01.lokana

import android.app.Notification
import android.app.Person
import android.os.Build
import android.os.Bundle
import android.os.Parcelable
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/**
 * Meneruskan notifikasi HP ke Lokana (NOTIF) dan panggilan masuk (CALL).
 *
 * Privasi: hanya aplikasi yang dipilih pengguna; yang dikirim hanya nama aplikasi, judul, dan
 * potongan isi (maks 160 karakter). Tidak ada yang disimpan di HP maupun di Lokana (hanya RAM).
 * Panggilan dideteksi dari notifikasi panggilan (CallStyle / full-screen), tanpa izin telepon.
 *
 * Callback berjalan di main thread, sama dengan BleLink.
 */
class NotifListener : NotificationListenerService() {
    companion object {
        private const val TAG = "LokanaNotif"
        private const val CALL_TYPE_INCOMING = 1     // Notification.CallStyle (Android 12+)
        var connected = false; private set
    }

    /** key notifikasi -> hash isi terakhir yang dikirim (lewati pembaruan yang sama persis) */
    private val sent = HashMap<String, Int>()
    private val ringing = HashSet<String>()
    private val labels = HashMap<String, String>()

    override fun onListenerConnected() {
        connected = true
        BleLink.init(this)
        BleLink.resume()                             // proses baru dihidupkan sistem: sambung lagi
    }

    override fun onListenerDisconnected() { connected = false }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try { handle(sbn) } catch (e: Exception) { Log.w(TAG, "notifikasi dilewati", e) }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        val key = sbn.key
        if (ringing.remove(key)) {
            BleLink.send(Proto.T_CALL, Proto.call(false, ""), true) {}
            return
        }
        if (sent.remove(key) != null && BleLink.state == BleLink.State.READY) {
            BleLink.send(Proto.T_NOTIF, Proto.notifDelete(idOf(key)), false) {}
        }
    }

    private fun idOf(key: String): Long = key.hashCode().toLong() and 0xFFFFFFFFL

    private fun handle(sbn: StatusBarNotification) {
        if (sbn.packageName == packageName) return
        val n = sbn.notification
        val ex = n.extras

        // ---- Panggilan masuk ----
        val callType = ex.getInt("android.callType", 0)
        if (n.category == Notification.CATEGORY_CALL || callType != 0) {
            if (!NotifPrefs.calls(this)) return
            val isRinging = callType == CALL_TYPE_INCOMING || (callType == 0 && n.fullScreenIntent != null)
            if (isRinging && ringing.add(sbn.key)) {
                val who = callerName(ex) ?: appLabel(sbn.packageName)
                Log.i(TAG, "panggilan masuk")
                BleLink.send(Proto.T_CALL, Proto.call(true, Proto.toAscii(who, 40)), true) {}
            } else if (!isRinging && ringing.remove(sbn.key)) {
                BleLink.send(Proto.T_CALL, Proto.call(false, ""), true) {}   // diangkat / ditolak
            }
            return
        }

        // ---- Notifikasi biasa ----
        if (!NotifPrefs.enabled(this) || sbn.packageName !in NotifPrefs.apps(this)) return
        if (n.flags and (Notification.FLAG_ONGOING_EVENT or Notification.FLAG_FOREGROUND_SERVICE) != 0) return
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return   // ringkasan grup: anak-anaknya dikirim
        if (BleLink.state != BleLink.State.READY) return

        val title = ex.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.let { conv ->
            val sender = ex.getCharSequence(Notification.EXTRA_TITLE)
            if (sender != null && sender != conv) "$conv: $sender" else conv
        } ?: ex.getCharSequence(Notification.EXTRA_TITLE)
        val body = lastMessage(ex) ?: ex.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: ex.getCharSequence(Notification.EXTRA_TEXT)
        val app = appLabel(sbn.packageName)
        val t = Proto.toAscii(title, 48)
        val b = Proto.toAscii(body, 160, keepNewline = true)
        if (t.isEmpty() && b.isEmpty()) return

        val hash = (app + "\u0000" + t + "\u0000" + b).hashCode()
        if (sent[sbn.key] == hash) return            // pembaruan tanpa perubahan isi
        sent[sbn.key] = hash
        if (sent.size > 64) sent.keys.firstOrNull()?.let { sent.remove(it) }

        val r = Ranking()
        val importance = if (currentRanking.getRanking(sbn.key, r)) r.importance else 3
        val silent = importance < 3                  // < IMPORTANCE_DEFAULT: tanpa bunyi
        val important = importance >= 4              // IMPORTANCE_HIGH
        BleLink.send(Proto.T_NOTIF,
            Proto.notif(idOf(sbn.key), category(n, sbn.packageName), silent, important,
                Proto.toAscii(app, 24), t, b), true) {}
    }

    private fun lastMessage(ex: Bundle): CharSequence? {
        val msgs = if (Build.VERSION.SDK_INT >= 33)
            ex.getParcelableArray(Notification.EXTRA_MESSAGES, Parcelable::class.java)
        else @Suppress("DEPRECATION") ex.getParcelableArray(Notification.EXTRA_MESSAGES)
        val last = msgs?.lastOrNull() as? Bundle ?: return null
        return last.getCharSequence("text")
    }

    private fun callerName(ex: Bundle): CharSequence? {
        if (Build.VERSION.SDK_INT >= 31) {
            val p = if (Build.VERSION.SDK_INT >= 33) ex.getParcelable(Notification.EXTRA_CALL_PERSON, Person::class.java)
            else @Suppress("DEPRECATION") ex.getParcelable<Person>(Notification.EXTRA_CALL_PERSON)
            p?.name?.let { return it }
        }
        return ex.getCharSequence(Notification.EXTRA_TITLE)
    }

    private fun appLabel(pkg: String): String = labels.getOrPut(pkg) {
        try {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
        } catch (_: Exception) { pkg.substringAfterLast('.') }
    }

    private fun category(n: Notification, pkg: String): Int = when (n.category) {
        Notification.CATEGORY_MESSAGE -> Proto.CAT_MESSAGE
        Notification.CATEGORY_EMAIL -> Proto.CAT_EMAIL
        Notification.CATEGORY_SOCIAL -> Proto.CAT_SOCIAL
        Notification.CATEGORY_EVENT, Notification.CATEGORY_REMINDER -> Proto.CAT_CALENDAR
        "missed_call" -> Proto.CAT_MISSED_CALL     // Notification.CATEGORY_MISSED_CALL (API 31)
        Notification.CATEGORY_SYSTEM, Notification.CATEGORY_STATUS -> Proto.CAT_SYSTEM
        else -> when {
            pkg.contains("whatsapp") || pkg.contains("telegram") || pkg.contains("messaging") -> Proto.CAT_MESSAGE
            pkg.contains("gm") && pkg.startsWith("com.google") -> Proto.CAT_EMAIL
            else -> Proto.CAT_GENERAL
        }
    }
}
