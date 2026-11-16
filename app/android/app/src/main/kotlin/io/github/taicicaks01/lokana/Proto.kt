package io.github.taicicaks01.lokana

import java.io.ByteArrayOutputStream
import java.util.TimeZone
import java.util.UUID

/**
 * Lokana Link v1: konstanta, frame, dan payload yang dibutuhkan sisi Kotlin
 * (HELLO, TIME_SYNC, SETTINGS GET, FIND_PHONE). Payload untuk layar lain dibuat di Dart.
 * Sumber kebenaran: protocol/LOKANA_LINK.md
 */
object Proto {
    val SERVICE: UUID = UUID.fromString("6c6f6b61-0000-4c4b-8000-6c6f6b616e61")
    val RX: UUID = UUID.fromString("6c6f6b61-0001-4c4b-8000-6c6f6b616e61")
    val TX: UUID = UUID.fromString("6c6f6b61-0002-4c4b-8000-6c6f6b616e61")
    val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    const val PROTO_VER = 1
    const val CLIENT_ANDROID = 1
    const val MAX_PAYLOAD = 1200
    const val RESYNC_MS = 1000L

    const val T_HELLO = 0x00
    const val T_TIME_SYNC = 0x01
    const val T_DEVICE_INFO = 0x02
    const val T_SETTINGS = 0x03
    const val T_ACK = 0x05
    const val T_FIND_PHONE = 0x21

    fun frame(type: Int, seq: Int, payload: ByteArray): ByteArray {
        val f = ByteArray(4 + payload.size)
        f[0] = type.toByte()
        f[1] = seq.toByte()
        f[2] = (payload.size and 0xFF).toByte()
        f[3] = (payload.size shr 8).toByte()
        payload.copyInto(f, 4)
        return f
    }

    private fun str(out: ByteArrayOutputStream, s: String) {
        val b = s.toByteArray(Charsets.UTF_8).let { if (it.size > 255) it.copyOf(255) else it }
        out.write(b.size)
        out.write(b)
    }

    fun hello(clientName: String): ByteArray {
        val o = ByteArrayOutputStream()
        o.write(PROTO_VER)
        o.write(CLIENT_ANDROID)
        str(o, clientName)
        return o.toByteArray()
    }

    fun timeSync(nowMs: Long = System.currentTimeMillis()): ByteArray {
        val epoch = nowMs / 1000
        val tz = TimeZone.getDefault().getOffset(nowMs) / 60000
        return byteArrayOf(
            (epoch and 0xFF).toByte(), (epoch shr 8 and 0xFF).toByte(),
            (epoch shr 16 and 0xFF).toByte(), (epoch shr 24 and 0xFF).toByte(),
            (tz and 0xFF).toByte(), (tz shr 8 and 0xFF).toByte(),
        )
    }

    fun settingsGet(): ByteArray = byteArrayOf(0)
}

/** Menyusun frame dari aliran byte notify BLE (frame boleh terpotong / tergabung). */
class FrameParser {
    data class Frame(val type: Int, val seq: Int, val payload: ByteArray)

    private val hdr = ByteArray(4)
    private var hn = 0
    private var len = 0
    private var got = 0
    private var tooBig = false
    private var last = 0L
    private var buf = ByteArray(Proto.MAX_PAYLOAD)

    fun reset() { hn = 0; got = 0; len = 0; tooBig = false }

    fun feed(data: ByteArray, now: Long, out: (Frame) -> Unit) {
        if (hn > 0 && now - last > Proto.RESYNC_MS) reset()
        last = now
        for (b in data) {
            if (hn < 4) {
                hdr[hn++] = b
                if (hn < 4) continue
                len = (hdr[2].toInt() and 0xFF) or ((hdr[3].toInt() and 0xFF) shl 8)
                got = 0
                tooBig = len > Proto.MAX_PAYLOAD
                if (len == 0) { hn = 0; out(Frame(hdr[0].toInt() and 0xFF, hdr[1].toInt() and 0xFF, ByteArray(0))) }
                continue
            }
            if (!tooBig) buf[got] = b
            if (++got < len) continue
            hn = 0
            if (!tooBig) out(Frame(hdr[0].toInt() and 0xFF, hdr[1].toInt() and 0xFF, buf.copyOf(len)))
        }
    }
}
