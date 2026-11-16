package io.github.taicicaks01.lokana

import android.content.Context
import android.content.SharedPreferences
import androidx.core.app.NotificationManagerCompat

/** Pilihan pengguna untuk penerusan notifikasi. Hanya aplikasi yang dicentang yang diteruskan. */
object NotifPrefs {
    private const val PREFS = "lokana_notif"

    /** Disarankan saat pertama kali dipakai (hanya yang terpasang yang dicentang). */
    private val SUGGESTED = setOf(
        "com.whatsapp", "com.whatsapp.w4b", "org.telegram.messenger", "com.google.android.apps.messaging",
        "com.android.mms", "com.google.android.gm", "com.instagram.android", "jp.naver.line.android",
        "com.discord", "com.facebook.orca", "com.google.android.calendar",
    )

    private fun prefs(c: Context): SharedPreferences = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun hasAccess(c: Context): Boolean =
        NotificationManagerCompat.getEnabledListenerPackages(c).contains(c.packageName)

    fun enabled(c: Context) = prefs(c).getBoolean("enabled", true)
    fun setEnabled(c: Context, on: Boolean) = prefs(c).edit().putBoolean("enabled", on).apply()

    fun calls(c: Context) = prefs(c).getBoolean("calls", true)
    fun setCalls(c: Context, on: Boolean) = prefs(c).edit().putBoolean("calls", on).apply()

    fun apps(c: Context): Set<String> {
        val p = prefs(c)
        if (!p.contains("apps")) {
            val installed = SUGGESTED.filter {
                try { c.packageManager.getApplicationInfo(it, 0); true } catch (_: Exception) { false }
            }.toSet()
            p.edit().putStringSet("apps", installed).apply()
            return installed
        }
        return p.getStringSet("apps", emptySet())!!.toSet()
    }

    fun setApp(c: Context, pkg: String, on: Boolean) {
        val s = apps(c).toMutableSet()
        if (on) s += pkg else s -= pkg
        prefs(c).edit().putStringSet("apps", s).apply()
    }
}
