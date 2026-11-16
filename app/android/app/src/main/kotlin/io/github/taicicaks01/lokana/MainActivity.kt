package io.github.taicicaks01.lokana

import android.Manifest
import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Jembatan Flutter <-> Kotlin.
 *  - MethodChannel "lokana/link": perintah dari UI (scan, connect, send, ...)
 *  - EventChannel  "lokana/events": state koneksi, hasil scan, frame dari Lokana
 */
class MainActivity : FlutterActivity() {
    private var events: EventChannel.EventSink? = null
    private var permResult: MethodChannel.Result? = null

    private val listener = object : BleLink.Listener {
        override fun onState(state: BleLink.State, address: String?, name: String?, message: String?) {
            events?.success(mapOf("event" to "state", "state" to state.id, "address" to address,
                "name" to name, "message" to message, "mtu" to BleLink.mtu, "action" to BleLink.action))
        }
        override fun onScan(address: String, name: String, rssi: Int) {
            events?.success(mapOf("event" to "scan", "address" to address, "name" to name, "rssi" to rssi))
        }
        override fun onFrame(type: Int, seq: Int, payload: ByteArray) {
            events?.success(mapOf("event" to "frame", "type" to type, "seq" to seq, "payload" to payload))
        }
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        BleLink.init(this)
        BleLink.resume()                                   // buka aplikasi = sambung lagi ke Lokana terakhir
        val messenger = engine.dartExecutor.binaryMessenger

        EventChannel(messenger, "lokana/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                events = sink
                BleLink.setListener(listener)
            }
            override fun onCancel(args: Any?) {
                events = null
                BleLink.setListener(null)
            }
        })

        MethodChannel(messenger, "lokana/link").setMethodCallHandler { call, result ->
            when (call.method) {
                "permissions" -> requestPermissions(result)
                "snapshot" -> result.success(mapOf(
                    "state" to BleLink.state.id,
                    "address" to BleLink.address,
                    "name" to BleLink.deviceName,
                    "mtu" to BleLink.mtu,
                    "saved" to BleLink.savedDevice()?.let { mapOf("address" to it.first, "name" to it.second) },
                    "deviceInfo" to BleLink.lastFrames[Proto.T_DEVICE_INFO],
                    "settings" to BleLink.lastFrames[Proto.T_SETTINGS],
                    "ringing" to Alarm.ringing,
                    "action" to BleLink.action,
                ))
                "startScan" -> result.success(BleLink.startScan())
                "stopScan" -> { BleLink.stopScan(); result.success(null) }
                "connect" -> result.success(BleLink.connect(call.argument<String>("address")!!, call.argument("name")))
                "disconnect" -> { BleLink.disconnect(call.argument<Boolean>("forget") == true); result.success(null) }
                "send" -> BleLink.send(call.argument<Int>("type")!!, call.argument<ByteArray>("payload") ?: ByteArray(0),
                    call.argument<Boolean>("ack") != false) { st -> result.success(st) }
                "phoneFound" -> { BleLink.phoneFound(); result.success(null) }
                "forget" -> BleLink.forget { ok -> result.success(ok) }
                "openBluetooth" -> { startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS)); result.success(null) }
                "pickImage" -> pickImage(result)
                "getPrefs" -> result.success(getSharedPreferences("lokana_app", MODE_PRIVATE).all
                    .mapValues { it.value.toString() })
                "setPref" -> {
                    getSharedPreferences("lokana_app", MODE_PRIVATE).edit()
                        .putString(call.argument<String>("key"), call.argument<String>("value")).apply()
                    result.success(null)
                }
                "saveImage" -> result.success(saveImage(call.argument<ByteArray>("bytes")!!, call.argument<String>("name")!!))

                // ---- Nada Cari HP (v0.5.2) ----
                "ringtoneInfo" -> result.success(mapOf("title" to Alarm.soundTitle(this), "custom" to (Alarm.customUri(this) != null)))
                "pickRingtone" -> pickRingtone(result)
                "pickRingtoneFile" -> pickRingtoneFile(result)
                "resetRingtone" -> { Alarm.setSound(this, null); result.success(Alarm.soundTitle(this)) }
                "previewRingtone" -> { Alarm.preview(this); result.success(null) }
                "stopPreview" -> { Alarm.stopPreview(); result.success(null) }

                // ---- Pengingat ketinggalan (v0.5.4) ----
                "leaveTest" -> { LeaveAlert.test(this); result.success(null) }
                "leaveSnooze" -> { LeaveAlert.snooze(this, call.argument<Int>("minutes") ?: 60); result.success(null) }
                "leaveInfo" -> result.success(mapOf("snoozeUntil" to LeaveAlert.snoozeUntil(this)))

                // ---- Notifikasi (v0.5) ----
                "notifStatus" -> result.success(mapOf(
                    "access" to NotifPrefs.hasAccess(this),
                    "enabled" to NotifPrefs.enabled(this),
                    "calls" to NotifPrefs.calls(this),
                    "apps" to NotifPrefs.apps(this).toList(),
                    "battery" to batteryUnrestricted(),
                ))
                "setNotif" -> {
                    call.argument<Boolean>("enabled")?.let { NotifPrefs.setEnabled(this, it) }
                    call.argument<Boolean>("calls")?.let { NotifPrefs.setCalls(this, it) }
                    call.argument<String>("app")?.let { NotifPrefs.setApp(this, it, call.argument<Boolean>("on") == true) }
                    result.success(null)
                }
                "installedApps" -> installedApps(result)
                "openNotifAccess" -> { startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)); result.success(null) }
                "openBattery" -> { openBatterySettings(); result.success(null) }
                "testNotif" -> BleLink.send(Proto.T_NOTIF, Proto.notif(0x4C4B, Proto.CAT_MESSAGE, false, false,
                    "Lokana", "Notifikasi uji", "Kalau ini tampil di Lokana, notifikasi sudah siap."), true) { result.success(it) }
                else -> result.notImplemented()
            }
        }
    }

    // ---------------- Screenshot ke galeri ----------------
    /** PNG ke Pictures/Lokana. Android 10+: MediaStore tanpa izin; lebih lama: folder aplikasi. */
    private fun saveImage(bytes: ByteArray, name: String): Boolean = try {
        if (Build.VERSION.SDK_INT >= 29) {
            val values = android.content.ContentValues().apply {
                put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, name)
                put(android.provider.MediaStore.Images.Media.MIME_TYPE, "image/png")
                put(android.provider.MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Lokana")
            }
            val uri = contentResolver.insert(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            uri != null && contentResolver.openOutputStream(uri)?.use { it.write(bytes); true } == true
        } else {
            val dir = java.io.File(getExternalFilesDir(android.os.Environment.DIRECTORY_PICTURES), "Lokana")
            dir.mkdirs()
            java.io.File(dir, name).writeBytes(bytes)
            true
        }
    } catch (_: Exception) { false }

    // ---------------- Pilih gambar / GIF ----------------
    private var pickResult: MethodChannel.Result? = null

    private fun pickImage(result: MethodChannel.Result) {
        pickResult?.success(null)
        pickResult = result
        val i = Intent(Intent.ACTION_GET_CONTENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE)
        @Suppress("DEPRECATION") startActivityForResult(Intent.createChooser(i, "Pilih gambar atau GIF"), 77)
    }

    // ---------------- Nada Cari HP ----------------
    private var ringResult: MethodChannel.Result? = null

    /** Pemilih nada sistem Android (alarm, dering, notifikasi). Hasil: nama nada, atau null jika batal. */
    private fun pickRingtone(result: MethodChannel.Result) {
        ringResult?.success(null)
        ringResult = result
        val i = Intent(android.media.RingtoneManager.ACTION_RINGTONE_PICKER)
            .putExtra(android.media.RingtoneManager.EXTRA_RINGTONE_TYPE, android.media.RingtoneManager.TYPE_ALL)
            .putExtra(android.media.RingtoneManager.EXTRA_RINGTONE_TITLE, "Nada Cari HP")
            .putExtra(android.media.RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, false)
            .putExtra(android.media.RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
            .putExtra(android.media.RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, Alarm.customUri(this))
        @Suppress("DEPRECATION") startActivityForResult(i, 78)
    }

    /** File audio sendiri (lagu, rekaman). Izin baca disimpan permanen supaya bisa diputar dari layanan. */
    private fun pickRingtoneFile(result: MethodChannel.Result) {
        ringResult?.success(null)
        ringResult = result
        val i = Intent(Intent.ACTION_OPEN_DOCUMENT).setType("audio/*").addCategory(Intent.CATEGORY_OPENABLE)
        @Suppress("DEPRECATION") startActivityForResult(i, 79)
    }

    private fun onRingtoneResult(requestCode: Int, resultCode: Int, data: Intent?) {
        val r = ringResult ?: return
        ringResult = null
        if (resultCode != RESULT_OK || data == null) { r.success(null); return }
        val uri: android.net.Uri? = if (requestCode == 78) {
            if (Build.VERSION.SDK_INT >= 33)
                data.getParcelableExtra(android.media.RingtoneManager.EXTRA_RINGTONE_PICKED_URI, android.net.Uri::class.java)
            else @Suppress("DEPRECATION") data.getParcelableExtra(android.media.RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        } else data.data?.also {
            try { contentResolver.takePersistableUriPermission(it, Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: Exception) {}
        }
        if (uri == null) { r.success(null); return }
        Alarm.setSound(this, uri)
        r.success(Alarm.soundTitle(this))
    }

    @Deprecated("startActivityForResult")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION") super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 78 || requestCode == 79) { onRingtoneResult(requestCode, resultCode, data); return }
        if (requestCode != 77) return
        val r = pickResult ?: return
        pickResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) { r.success(null); return }
        Executors.newSingleThreadExecutor().execute {
            val bytes = try {
                contentResolver.openInputStream(uri)?.use { s ->
                    val b = s.readBytes()
                    if (b.size > 8 * 1024 * 1024) null else b       // maks 8 MB
                }
            } catch (_: Exception) { null }
            Handler(Looper.getMainLooper()).post { r.success(bytes) }
        }
    }

    // ---------------- Notifikasi & baterai ----------------
    private fun batteryUnrestricted(): Boolean =
        (getSystemService(POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName)

    /** Koneksi BLE & notifikasi butuh aplikasi tidak dihentikan penghemat baterai (terutama HP Infinix/Xiaomi). */
    @SuppressLint("BatteryLife")
    private fun openBatterySettings() {
        try {
            startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
        } catch (_: Exception) {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }

    /** Aplikasi yang muncul di peluncur: nama, paket, ikon PNG 72 px. Dikerjakan di thread lain. */
    private fun installedApps(result: MethodChannel.Result) {
        val pm = packageManager
        val main = Handler(Looper.getMainLooper())
        Executors.newSingleThreadExecutor().execute {
            val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
            val list = pm.queryIntentActivities(intent, 0)
                .map { it.activityInfo.applicationInfo }
                .distinctBy { it.packageName }
                .filter { it.packageName != packageName }
                .map { ai ->
                    val icon = try {
                        val d = pm.getApplicationIcon(ai)
                        val bmp = Bitmap.createBitmap(72, 72, Bitmap.Config.ARGB_8888)
                        d.setBounds(0, 0, 72, 72)
                        d.draw(Canvas(bmp))
                        ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
                    } catch (_: Exception) { null }
                    mapOf("package" to ai.packageName, "label" to pm.getApplicationLabel(ai).toString(), "icon" to icon)
                }
                .sortedBy { (it["label"] as String).lowercase() }
            main.post { result.success(list) }
        }
    }

    // ---------------- Izin runtime ----------------
    private fun neededPermissions(): List<String> {
        val p = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 31) {
            p += Manifest.permission.BLUETOOTH_SCAN
            p += Manifest.permission.BLUETOOTH_CONNECT
        } else {
            p += Manifest.permission.ACCESS_FINE_LOCATION   // scan BLE di Android 11 ke bawah
        }
        if (Build.VERSION.SDK_INT >= 33) p += Manifest.permission.POST_NOTIFICATIONS
        return p.filter { ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED }
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        val missing = neededPermissions()
        if (missing.isEmpty()) { result.success(true); return }
        permResult?.success(false)
        permResult = result
        ActivityCompat.requestPermissions(this, missing.toTypedArray(), 42)
    }

    override fun onRequestPermissionsResult(code: Int, perms: Array<out String>, grants: IntArray) {
        super.onRequestPermissionsResult(code, perms, grants)
        if (code != 42) return
        // Notifikasi boleh ditolak; Bluetooth (dan lokasi di Android lama) wajib
        val ok = neededPermissions().none { it != Manifest.permission.POST_NOTIFICATIONS }
        permResult?.success(ok)
        permResult = null
    }
}
