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
    const val T_UNPAIR = 0x06
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

    const val T_NOTIF = 0x10
    const val T_CALL = 0x15

    // Kategori NOTIF
    const val CAT_GENERAL = 0
    const val CAT_MESSAGE = 1
    const val CAT_EMAIL = 2
    const val CAT_SOCIAL = 3
    const val CAT_CALENDAR = 4
    const val CAT_MISSED_CALL = 5
    const val CAT_SYSTEM = 6

    private fun u32(o: ByteArrayOutputStream, v: Long) {
        for (i in 0 until 4) o.write((v shr (8 * i) and 0xFF).toInt())
    }

    /** NOTIF op 0. Teks sebaiknya sudah lewat [toAscii]; panjang dipotong sesuai spesifikasi. */
    fun notif(id: Long, category: Int, silent: Boolean, important: Boolean,
              app: String, title: String, body: String): ByteArray {
        val o = ByteArrayOutputStream()
        o.write(0)
        u32(o, id)
        o.write(category)
        o.write((if (silent) 1 else 0) or (if (important) 2 else 0))
        str(o, app.take(24))
        str(o, title.take(48))
        str(o, body.take(160))
        return o.toByteArray()
    }

    fun notifDelete(id: Long): ByteArray {
        val o = ByteArrayOutputStream()
        o.write(1)
        u32(o, id)
        return o.toByteArray()
    }

    fun call(ringing: Boolean, caller: String): ByteArray {
        val o = ByteArrayOutputStream()
        o.write(if (ringing) 0 else 1)
        str(o, caller.take(40))
        return o.toByteArray()
    }

    /**
     * Font OLED hanya ASCII: huruf beraksen jadi huruf dasar (é -> e), tanda kutip/pisah
     * diganti padanannya, emoji & simbol dibuang, karakter lain jadi '?'.
     */
    fun toAscii(s: CharSequence?, max: Int = 255, keepNewline: Boolean = false): String {
        if (s.isNullOrEmpty()) return ""
        val norm = java.text.Normalizer.normalize(s, java.text.Normalizer.Form.NFD)
        val sb = StringBuilder()
        var i = 0
        while (i < norm.length && sb.length < max) {
            val cp = norm.codePointAt(i)
            i += Character.charCount(cp)
            val type = Character.getType(cp)
            when {
                cp == '\n'.code -> sb.append(if (keepNewline) '\n' else ' ')
                cp in 32..126 -> sb.append(cp.toChar())
                type == Character.NON_SPACING_MARK.toInt() -> {}            // aksen setelah NFD
                cp == 0x2018 || cp == 0x2019 -> sb.append('\'')
                cp == 0x201C || cp == 0x201D -> sb.append('"')
                cp == 0x2013 || cp == 0x2014 -> sb.append('-')
                cp == 0x2026 -> sb.append("...")
                Character.isWhitespace(cp) || Character.isSpaceChar(cp) -> sb.append(' ')
                cp == 0x200D || cp in 0xFE00..0xFE0F || cp >= 0x1F000 ||
                    type == Character.OTHER_SYMBOL.toInt() || type == Character.FORMAT.toInt() -> {}   // emoji
                else -> sb.append('?')
            }
        }
        return sb.toString().replace(Regex("[ ]{2,}"), " ").trim()
    }
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
