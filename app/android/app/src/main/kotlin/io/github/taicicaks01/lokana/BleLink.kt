package io.github.taicicaks01.lokana

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.os.SystemClock
import android.Manifest
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Koneksi BLE ke Lokana (GATT client) + Lokana Link: framing, seq, ACK & kirim ulang.
 * Hidup di proses aplikasi (dijaga LinkService), terpisah dari UI Flutter,
 * supaya Cari HP tetap jalan saat aplikasi di latar belakang.
 *
 * Semua state diubah di main thread (callback GATT diteruskan lewat handler).
 */
@SuppressLint("MissingPermission")   // izin dicek MainActivity sebelum scan/connect
object BleLink {
    private const val TAG = "LokanaBle"
    private const val ACK_TIMEOUT_MS = 2000L
    private const val RETRIES = 3
    private const val PREFS = "lokana"
    const val CLIENT_NAME = "Lokana Android 0.5.5"

    enum class State(val id: String) {
        IDLE("idle"), SCANNING("scanning"), CONNECTING("connecting"), PAIRING("pairing"),
        READY("ready"), RECONNECTING("reconnecting"),
    }

    interface Listener {
        fun onState(state: State, address: String?, name: String?, message: String?)
        fun onScan(address: String, name: String, rssi: Int)
        fun onFrame(type: Int, seq: Int, payload: ByteArray)
    }

    private val main = Handler(Looper.getMainLooper())
    private lateinit var app: Context
    private var listener: Listener? = null

    var state = State.IDLE; private set
    var address: String? = null; private set
    var deviceName: String? = null; private set
    var mtu = 23; private set
    /** Saran tindakan untuk UI: "bt_settings" = pengguna perlu menghapus pairing di Pengaturan Bluetooth. */
    var action: String? = null; private set
    /** Frame terakhir per type (DEVICE_INFO, SETTINGS) untuk UI yang baru dibuka. */
    val lastFrames = HashMap<Int, ByteArray>()

    private var gatt: BluetoothGatt? = null
    private var rx: BluetoothGattCharacteristic? = null
    private var userDisconnect = false
    private var connectedAt = 0L                 // elapsedRealtime saat link fisik tersambung
    private var staleRetries = 0                 // percobaan perbaikan bond lama
    // RSSI koneksi siap, diukur tiap 2,5 detik (pengingat ketinggalan: dekat = dimatikan, jauh = tertinggal)
    private var rssi: Int? = null
    private var rssiAt = 0L
    /** RSSI terakhir (dBm) selama tersambung, null jika belum terukur / sudah basi (> 10 dtk). Untuk chip sinyal. */
    fun lastRssi(): Int? =
        if (state == State.READY && rssiAt > 0 && SystemClock.elapsedRealtime() - rssiAt < 10_000) rssi else null

    private val rssiTick = object : Runnable {
        override fun run() {
            if (state != State.READY) return
            if (!writing) try { gatt?.readRemoteRssi() } catch (e: SecurityException) { Log.w(TAG, "rssi", e) }
            main.postDelayed(this, 2500)
        }
    }
    private var bondReceiver: BroadcastReceiver? = null
    private val parser = FrameParser()

    // Antrian tulis: Android hanya boleh satu operasi GATT berjalan
    private val writeQueue = ArrayDeque<ByteArray>()
    private var writing = false

    private class Pending(val frame: ByteArray, val done: (Int) -> Unit) {
        var tries = 0
        var timeout: Runnable? = null
    }
    private val pending = HashMap<Int, Pending>()
    private var seq = 0

    fun init(context: Context) {
        if (::app.isInitialized) return
        app = context.applicationContext
        ContextCompat.registerReceiver(app, btState, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED),
            ContextCompat.RECEIVER_NOT_EXPORTED)
    }

    // Bluetooth HP dinyalakan lagi: percobaan sambung saat Bluetooth mati sudah gagal, jadi mulai lagi
    private val btState = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            if (i.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1) != BluetoothAdapter.STATE_ON) return
            main.postDelayed({
                if (userDisconnect || state == State.READY) return@postDelayed
                Log.i(TAG, "Bluetooth menyala lagi, menyambung ulang")
                if (state == State.IDLE) { resume(); return@postDelayed }
                val addr = address ?: savedDevice()?.first ?: return@postDelayed
                val a = adapter() ?: return@postDelayed
                closeGatt()
                open(a.getRemoteDevice(addr), autoConnect = true)
            }, 1500)
        }
    }

    fun setListener(l: Listener?) { listener = l }

    private fun adapter(): BluetoothAdapter? =
        (app.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter

    private fun setState(s: State, message: String? = null) {
        state = s
        listener?.onState(s, address, deviceName, message)
    }

    fun savedDevice(): Pair<String, String>? {
        val p = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val a = p.getString("address", null) ?: return null
        return a to (p.getString("name", null) ?: "Lokana")
    }

    /** Sambung otomatis ke Lokana terakhir: aktif setelah connect(), mati setelah pengguna memutus. */
    private fun setAuto(on: Boolean) =
        app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("auto", on).apply()

    /**
     * Dipanggil saat proses/UI hidup lagi (aplikasi dibuka, NotificationListener tersambung,
     * service dihidupkan ulang sistem): sambung lagi jika pengguna tidak memutus sendiri.
     */
    fun resume() {
        if (state != State.IDLE) return
        if (!app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("auto", false)) return
        if (Build.VERSION.SDK_INT >= 31 &&
            ContextCompat.checkSelfPermission(app, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) return
        val (a, n) = savedDevice() ?: return
        Log.i(TAG, "menyambung lagi ke $n")
        connect(a, n)
    }

    private fun save(a: String?, n: String?) {
        app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().apply {
            if (a == null) remove("address").remove("name") else putString("address", a).putString("name", n)
        }.apply()
    }

    // ---------------- Scan ----------------
    private val scanCb = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, r: ScanResult) {
            val name = r.scanRecord?.deviceName ?: r.device.name ?: "Lokana"
            main.post { listener?.onScan(r.device.address, name, r.rssi) }
        }
        override fun onScanFailed(errorCode: Int) {
            main.post { setState(State.IDLE, "Scan gagal ($errorCode)") }
        }
    }
    private val stopScanRunnable = Runnable { stopScan() }

    fun startScan(): String? {
        val a = adapter() ?: return "Bluetooth tidak ada di HP ini"
        if (!a.isEnabled) return "Nyalakan Bluetooth dulu"
        val scanner = a.bluetoothLeScanner ?: return "Bluetooth belum siap"
        if (state == State.SCANNING) stopScan()
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(Proto.SERVICE)).build()
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        scanner.startScan(listOf(filter), settings, scanCb)
        setState(State.SCANNING)
        main.postDelayed(stopScanRunnable, 15000)
        return null
    }

    fun stopScan() {
        main.removeCallbacks(stopScanRunnable)
        try { adapter()?.bluetoothLeScanner?.stopScan(scanCb) } catch (e: Exception) { Log.w(TAG, "stopScan", e) }
        if (state == State.SCANNING) setState(State.IDLE)
    }

    // ---------------- Sambung ----------------
    fun connect(addr: String, name: String?): String? {
        val a = adapter() ?: return "Bluetooth tidak ada di HP ini"
        if (!a.isEnabled) return "Nyalakan Bluetooth dulu"
        if (state == State.SCANNING) stopScan()
        closeGatt()
        userDisconnect = false
        action = null
        staleRetries = 0
        setAuto(true)
        address = addr
        deviceName = name ?: savedDevice()?.second
        LinkService.start(app)
        open(a.getRemoteDevice(addr), autoConnect = false)
        return null
    }

    private fun open(device: BluetoothDevice, autoConnect: Boolean) {
        setState(if (autoConnect) State.RECONNECTING else State.CONNECTING)
        parser.reset()
        mtu = 23
        gatt = device.connectGatt(app, autoConnect, gattCb, BluetoothDevice.TRANSPORT_LE)
    }

    fun disconnect(forget: Boolean) {
        userDisconnect = true
        setAuto(false)
        main.removeCallbacksAndMessages(null)
        closeGatt()
        failAllPending()
        if (forget) save(null, null)
        setState(State.IDLE)
        LinkService.stop(app)
        Alarm.stop(app)
        LeaveAlert.cancel(app)
    }

    /**
     * Lupakan Lokana ini di dua sisi: kirim UNPAIR (Lokana menghapus bond HP ini), lalu hapus
     * bond di HP dan alamat tersimpan. Sambungan berikutnya meminta kode 6 digit baru.
     */
    fun forget(done: (Boolean) -> Unit) {
        val dev = address?.let { adapter()?.getRemoteDevice(it) } ?: savedDevice()?.let { adapter()?.getRemoteDevice(it.first) }
        val finish = { lokanaForgot: Boolean ->
            disconnect(forget = true)
            val phoneForgot = dev == null || dev.bondState == BluetoothDevice.BOND_NONE || removeBond(dev)
            done(lokanaForgot && phoneForgot)
        }
        if (state == State.READY) send(Proto.T_UNPAIR, ByteArray(0), true) { st -> finish(st == 0) }
        else finish(false)
    }

    /** API tersembunyi Android, tapi tersedia di hampir semua HP. false jika ditolak. */
    private fun removeBond(device: BluetoothDevice): Boolean = try {
        device.javaClass.getMethod("removeBond").invoke(device) as Boolean
    } catch (e: Exception) {
        Log.w(TAG, "removeBond tidak tersedia", e); false
    }

    private fun closeGatt() {
        unregisterBond()
        gatt?.let { try { it.disconnect(); it.close() } catch (e: Exception) { Log.w(TAG, "close", e) } }
        gatt = null
        rx = null
        writeQueue.clear()
        writing = false
    }

    private fun scheduleReconnect() {
        val addr = address ?: return
        main.postDelayed({
            if (userDisconnect || state == State.READY) return@postDelayed
            val a = adapter() ?: return@postDelayed
            closeGatt()
            // autoConnect = true: Android menyambung sendiri begitu Lokana dalam jangkauan
            open(a.getRemoteDevice(addr), autoConnect = true)
        }, 2000)
    }

    private val gattCb = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            main.post {
                if (g != gatt) return@post
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    connectedAt = SystemClock.elapsedRealtime()
                    Log.i(TAG, "tersambung, minta MTU 247")
                    setState(State.CONNECTING)
                    g.requestMtu(247)
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    Log.i(TAG, "terputus status=$status")
                    val wasReady = state == State.READY
                    val device = g.device
                    val quick = connectedAt > 0 && SystemClock.elapsedRealtime() - connectedAt < 8000
                    connectedAt = 0
                    closeGatt()
                    failAllPending()
                    if (userDisconnect) { setState(State.IDLE); return@post }
                    main.removeCallbacks(rssiTick)
                    if (wasReady) {
                        val age = if (rssiAt > 0) SystemClock.elapsedRealtime() - rssiAt else Long.MAX_VALUE
                        LeaveAlert.lost(app, status, rssi, age)
                    }
                    rssi = null
                    rssiAt = 0
                    // HP masih menyimpan bond, tapi Lokana sudah melupakannya (menu "Lupakan HP"):
                    // Lokana menolak enkripsi lalu memutus. Hapus bond lama di HP, pairing ulang.
                    if (!wasReady && quick && device.bondState == BluetoothDevice.BOND_BONDED) {
                        if (staleRetries < 1 && removeBond(device)) {
                            staleRetries++
                            setState(State.PAIRING, "Lokana tidak mengenali pairing lama. Memulai pairing ulang...")
                            main.postDelayed({
                                if (!userDisconnect) adapter()?.let { open(it.getRemoteDevice(device.address), autoConnect = false) }
                            }, 1500)
                            return@post
                        }
                        action = "bt_settings"
                        userDisconnect = true             // jangan coba terus-menerus
                        setState(State.IDLE, "Hapus \"${deviceName ?: "Lokana"}\" di Pengaturan Bluetooth HP, lalu sambungkan lagi")
                        return@post
                    }
                    setState(State.RECONNECTING, if (wasReady) "Lokana terputus" else "Gagal tersambung ($status)")
                    scheduleReconnect()
                }
            }
        }

        override fun onReadRemoteRssi(g: BluetoothGatt, r: Int, status: Int) {
            main.post {
                if (g == gatt && status == BluetoothGatt.GATT_SUCCESS) { rssi = r; rssiAt = SystemClock.elapsedRealtime() }
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, newMtu: Int, status: Int) {
            main.post {
                if (g != gatt) return@post
                if (status == BluetoothGatt.GATT_SUCCESS) mtu = newMtu
                g.discoverServices()
            }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            main.post {
                if (g != gatt) return@post
                val svc = g.getService(Proto.SERVICE)
                val tx = svc?.getCharacteristic(Proto.TX)
                rx = svc?.getCharacteristic(Proto.RX)
                if (tx == null || rx == null) {
                    setState(State.RECONNECTING, "Bukan perangkat Lokana")
                    disconnect(forget = false)
                    return@post
                }
                g.setCharacteristicNotification(tx, true)
                val d = tx.getDescriptor(Proto.CCCD)
                val v = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                if (Build.VERSION.SDK_INT >= 33) g.writeDescriptor(d, v)
                else { @Suppress("DEPRECATION") run { d.value = v; g.writeDescriptor(d) } }
            }
        }

        override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int) {
            main.post {
                if (g != gatt) return@post
                // Lokana meminta keamanan saat tersambung: HP baru -> dialog kode 6 digit dari Android
                if (g.device.bondState == BluetoothDevice.BOND_BONDED) onSecure()
                else waitForBond(g.device)
            }
        }

        override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            main.post {
                if (g != gatt) return@post
                if (status != BluetoothGatt.GATT_SUCCESS) Log.w(TAG, "tulis gagal status=$status")
                writing = false
                writeNext()
            }
        }

        @Deprecated("API < 33")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            @Suppress("DEPRECATION") val v = c.value ?: return
            val copy = v.copyOf()
            main.post { if (g == gatt) onNotify(copy) }
        }

        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray) {
            main.post { if (g == gatt) onNotify(value) }
        }
    }

    private fun waitForBond(device: BluetoothDevice) {
        setState(State.PAIRING, "Ketik kode 6 digit yang tampil di layar Lokana")
        unregisterBond()
        val r = object : BroadcastReceiver() {
            override fun onReceive(c: Context, i: Intent) {
                val d: BluetoothDevice? = if (Build.VERSION.SDK_INT >= 33)
                    i.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                else @Suppress("DEPRECATION") i.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                if (d?.address != address) return
                when (i.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, -1)) {
                    BluetoothDevice.BOND_BONDED -> { unregisterBond(); main.postDelayed({ onSecure() }, 400) }
                    BluetoothDevice.BOND_NONE -> {
                        unregisterBond()
                        setState(State.PAIRING, "Pairing gagal. Coba sambungkan lagi")
                    }
                }
            }
        }
        bondReceiver = r
        ContextCompat.registerReceiver(app, r, IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED),
            ContextCompat.RECEIVER_EXPORTED)
        // Sudah bonded saat receiver dipasang?
        if (device.bondState == BluetoothDevice.BOND_BONDED) { unregisterBond(); onSecure() }
    }

    private fun unregisterBond() {
        bondReceiver?.let { try { app.unregisterReceiver(it) } catch (_: Exception) {} }
        bondReceiver = null
    }

    /** Terenkripsi & bonded: perkenalan, sinkron jam, baca pengaturan. */
    private fun onSecure() {
        if (gatt == null || state == State.READY) return
        save(address, deviceName)
        staleRetries = 0
        action = null
        setState(State.READY)
        LeaveAlert.back(app)
        main.removeCallbacks(rssiTick)
        main.postDelayed(rssiTick, 1000)
        send(Proto.T_HELLO, Proto.hello(CLIENT_NAME), true) { st ->
            if (st != 0) Log.w(TAG, "HELLO status=$st")
            send(Proto.T_TIME_SYNC, Proto.timeSync(), true) {}
            send(Proto.T_SETTINGS, Proto.settingsGet(), true) {}
        }
    }

    // ---------------- Kirim / terima ----------------
    /** Kirim frame. ack = true: tunggu ACK (2 dtk, kirim ulang maks 3x). done(status), -1 = tanpa ACK. */
    fun send(type: Int, payload: ByteArray, ack: Boolean, done: (Int) -> Unit) {
        if (state != State.READY || rx == null) { done(-2); return }
        if (payload.size > Proto.MAX_PAYLOAD) { done(2); return }
        if (!ack) { enqueue(Proto.frame(type, 0, payload)); done(0); return }
        seq = seq % 255 + 1
        val s = seq
        pending.remove(s)?.let { p -> p.timeout?.let { main.removeCallbacks(it) }; p.done(-1) }
        val p = Pending(Proto.frame(type, s, payload), done)
        pending[s] = p
        attempt(s, p)
    }

    private fun attempt(s: Int, p: Pending) {
        p.tries++
        enqueue(p.frame)
        val t = Runnable {
            if (pending[s] !== p) return@Runnable
            if (p.tries < RETRIES && state == State.READY) attempt(s, p)
            else { pending.remove(s); p.done(-1) }
        }
        p.timeout = t
        main.postDelayed(t, ACK_TIMEOUT_MS)
    }

    private fun failAllPending() {
        val all = pending.values.toList()
        pending.clear()
        for (p in all) { p.timeout?.let { main.removeCallbacks(it) }; p.done(-2) }
    }

    private fun enqueue(frame: ByteArray) {
        val chunk = (mtu - 3).coerceAtLeast(20)
        var i = 0
        while (i < frame.size) {
            writeQueue.addLast(frame.copyOfRange(i, minOf(frame.size, i + chunk)))
            i += chunk
        }
        writeNext()
    }

    private fun writeNext() {
        if (writing) return
        val g = gatt ?: return
        val c = rx ?: return
        val data = writeQueue.removeFirstOrNull() ?: return
        writing = true
        val ok = if (Build.VERSION.SDK_INT >= 33) {
            g.writeCharacteristic(c, data, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) == BluetoothGatt.GATT_SUCCESS
        } else @Suppress("DEPRECATION") run {
            c.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            c.value = data
            g.writeCharacteristic(c)
        }
        if (!ok) {                                   // stack sibuk: coba lagi sebentar lagi
            writing = false
            writeQueue.addFirst(data)
            main.postDelayed({ writeNext() }, 30)
        }
    }

    private fun onNotify(data: ByteArray) {
        parser.feed(data, SystemClock.elapsedRealtime()) { f -> onFrame(f) }
    }

    private fun onFrame(f: FrameParser.Frame) {
        if (f.type == Proto.T_ACK) {
            if (f.payload.size >= 2) {
                pending.remove(f.seq)?.let { p ->
                    p.timeout?.let { main.removeCallbacks(it) }
                    p.done(f.payload[1].toInt() and 0xFF)
                }
            }
            return
        }
        if (f.type == Proto.T_DEVICE_INFO || f.type == Proto.T_SETTINGS) lastFrames[f.type] = f.payload
        if (f.type == Proto.T_FIND_PHONE && f.payload.isNotEmpty()) {
            if (f.payload[0].toInt() != 0) Alarm.start(app) else Alarm.stop(app)
        }
        listener?.onFrame(f.type, f.seq, f.payload)
    }

    /** Hentikan bunyi Cari HP dari HP: beri tahu Lokana supaya layarnya ditutup. */
    fun phoneFound() {
        Alarm.stop(app)
        send(Proto.T_FIND_PHONE, byteArrayOf(0), true) {}
    }
}
