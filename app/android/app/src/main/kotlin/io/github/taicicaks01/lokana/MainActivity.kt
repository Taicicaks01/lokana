package io.github.taicicaks01.lokana

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
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
                "name" to name, "message" to message, "mtu" to BleLink.mtu))
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
                ))
                "startScan" -> result.success(BleLink.startScan())
                "stopScan" -> { BleLink.stopScan(); result.success(null) }
                "connect" -> result.success(BleLink.connect(call.argument<String>("address")!!, call.argument("name")))
                "disconnect" -> { BleLink.disconnect(call.argument<Boolean>("forget") == true); result.success(null) }
                "send" -> BleLink.send(call.argument<Int>("type")!!, call.argument<ByteArray>("payload") ?: ByteArray(0),
                    call.argument<Boolean>("ack") != false) { st -> result.success(st) }
                "phoneFound" -> { BleLink.phoneFound(); result.success(null) }
                else -> result.notImplemented()
            }
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
